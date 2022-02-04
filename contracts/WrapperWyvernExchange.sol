//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import './interfaces/IWyvernExchange.sol';
import './interfaces/IRoyaltyEngine.sol';

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import 'hardhat/console.sol';

// TODO:
/* 
    - atomic match functionality 
    - pausability
    - royalty payouts 
    - changing royalty engine
    */

// Hot wallet used to store funds and distribute fees

contract ERC20Basic {
  // function totalSupply() public view returns (uint256);

  // function balanceOf(address who) public view returns (uint256);

  // function transfer(address to, uint256 value) public returns (bool);

  // event Transfer(address indexed from, address indexed to, uint256 value);
}

contract ERC20 is ERC20Basic {
  // function allowance(address owner, address spender) public view returns (uint256);

  // function transferFrom(
  //   address from,
  //   address to,
  //   uint256 value
  // ) public returns (bool);

  // function approve(address spender, uint256 value) public returns (bool);

  // event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract OwnedUpgradeabilityStorage {
  // Current implementation
  address internal _implementation;

  // Owner of the contract
  address private _upgradeabilityOwner;

  /**
   * @dev Tells the address of the owner
   * @return the address of the owner
   */
  function upgradeabilityOwner() public view returns (address) {
    return _upgradeabilityOwner;
  }

  /**
   * @dev Sets the address of the owner
   */
  function setUpgradeabilityOwner(address newUpgradeabilityOwner) internal {
    _upgradeabilityOwner = newUpgradeabilityOwner;
  }

  /**
   * @dev Tells the address of the current implementation
   * @return address of the current implementation
   */
  function implementation() public view returns (address) {
    return _implementation;
  }
  function proxyType() public pure returns (uint256 proxyTypeId) {
    return 2;
  }
}

contract TokenRecipient {
  event ReceivedEther(address indexed sender, uint256 amount);
  event ReceivedTokens(address indexed from, uint256 value, address indexed token, bytes extraData);  
}

contract AuthenticatedProxy is TokenRecipient, OwnedUpgradeabilityStorage {
  /* Whether initialized. */
  bool initialized = false;

  /* Address which owns this proxy. */
  address public user;

  /* Associated registry with contract authentication information. */
  ProxyRegistry public registry;

  /* Whether access has been revoked. */
  bool public revoked;

  /* Delegate call could be used to atomically transfer multiple assets owned by the proxy contract with one order. */
  enum HowToCall {
    Call,
    DelegateCall
  }

  /* Event fired when the proxy access is revoked or unrevoked. */
  event Revoked(bool revoked);

  /**
   * Initialize an AuthenticatedProxy
   *
   * @param addrUser Address of user on whose behalf this proxy will act
   * @param addrRegistry Address of ProxyRegistry contract which will manage this proxy
   */
  function initialize(address addrUser, ProxyRegistry addrRegistry) public {
    require(!initialized);
    initialized = true;
    user = addrUser;
    registry = addrRegistry;
  }

  /**
   * Set the revoked flag (allows a user to revoke ProxyRegistry access)
   *
   * @dev Can be called by the user only
   * @param revoke Whether or not to revoke access
   */
  function setRevoke(bool revoke) public {
    require(msg.sender == user);
    revoked = revoke;
    emit Revoked(revoke);
  }
}

contract Proxy {
}

contract OwnedUpgradeabilityProxy is Proxy, OwnedUpgradeabilityStorage {
  /**
   * @dev Event to show ownership has been transferred
   * @param previousOwner representing the address of the previous owner
   * @param newOwner representing the address of the new owner
   */
  event ProxyOwnershipTransferred(address previousOwner, address newOwner);

  /**
   * @dev This event will be emitted every time the implementation gets upgraded
   * @param implementation representing the address of the upgraded implementation
   */
  event Upgraded(address indexed implementation);

  /**
   * @dev Upgrades the implementation address
   * @param implementation representing the address of the new implementation to be set
   */
  function _upgradeTo(address implementation) internal {
    require(_implementation != implementation);
    _implementation = implementation;
    emit Upgraded(implementation);
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyProxyOwner() {
    require(msg.sender == proxyOwner());
    _;
  }

  /**
   * @dev Tells the address of the proxy owner
   * @return the address of the proxy owner
   */
  function proxyOwner() public view returns (address) {
    return upgradeabilityOwner();
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferProxyOwnership(address newOwner) public onlyProxyOwner {
    require(newOwner != address(0));
    emit ProxyOwnershipTransferred(proxyOwner(), newOwner);
    setUpgradeabilityOwner(newOwner);
  }

  /**
   * @dev Allows the upgradeability owner to upgrade the current implementation of the proxy.
   * @param implementation representing the address of the new implementation to be set.
   */
  function upgradeTo(address implementation) public onlyProxyOwner {
    _upgradeTo(implementation);
  }

  /**
   * @dev Allows the upgradeability owner to upgrade the current implementation of the proxy
   * and delegatecall the new implementation for initialization.
   * @param implementation representing the address of the new implementation to be set.
   * @param data represents the msg.data to bet sent in the low level call. This parameter may include the function
   * signature of the implementation to be called with the needed payload
   */
  // function upgradeToAndCall(address implementation, bytes memory data) public payable onlyProxyOwner {
  //   upgradeTo(implementation);
  //   require(address(this).delegatecall(data));
  // }
}

contract OwnableDelegateProxy is OwnedUpgradeabilityProxy {
  constructor(
    address owner,
    address initialImplementation,
    bytes memory
  ) public {
    setUpgradeabilityOwner(owner);
    _upgradeTo(initialImplementation);
    // require(initialImplementation.delegatecall(calldata));
  }
}

contract ProxyRegistry is Ownable {
  /* DelegateProxy implementation contract. Must be initialized. */
  address public delegateProxyImplementation;

  /* Authenticated proxies by user. */
  mapping(address => OwnableDelegateProxy) public proxies;

  /* Contracts pending access. */
  mapping(address => uint256) public pending;

  /* Contracts allowed to call those proxies. */
  mapping(address => bool) public contracts;

  /* Delay period for adding an authenticated contract.
       This mitigates a particular class of potential attack on the Wyvern DAO (which owns this registry) - if at any point the value of assets held by proxy contracts exceeded the value of half the WYV supply (votes in the DAO),
       a malicious but rational attacker could buy half the Wyvern and grant themselves access to all the proxy contracts. A delay period renders this attack nonthreatening - given two weeks, if that happened, users would have
       plenty of time to notice and transfer their assets.
    */
  uint256 public DELAY_PERIOD = 2 weeks;

  /**
   * Start the process to enable access for specified contract. Subject to delay period.
   *
   * @dev ProxyRegistry owner only
   * @param addr Address to which to grant permissions
   */
  // function startGrantAuthentication(address addr) public onlyOwner {
  //   require(!contracts[addr] && pending[addr] == 0);
  //   pending[addr] = now;
  // }

  /**
   * End the process to nable access for specified contract after delay period has passed.
   *
   * @dev ProxyRegistry owner only
   * @param addr Address to which to grant permissions
   */
  // function endGrantAuthentication(address addr) public onlyOwner {
  //   require(!contracts[addr] && pending[addr] != 0 && ((pending[addr] + DELAY_PERIOD) < now));
  //   pending[addr] = 0;
  //   contracts[addr] = true;
  // }

  /**
   * Revoke access for specified contract. Can be done instantly.
   *
   * @dev ProxyRegistry owner only
   * @param addr Address of which to revoke permissions
   */
  function revokeAuthentication(address addr) public onlyOwner {
    contracts[addr] = false;
  }

  /**
   * Register a proxy contract with this registry
   *
   * @dev Must be called by the user which the proxy is for, creates a new AuthenticatedProxy
   * @return proxy AuthenticatedProxy contract
   */
  // function registerProxy() public returns (OwnableDelegateProxy proxy) {
  //   require(proxies[msg.sender] == address(0));
  //   proxy = new OwnableDelegateProxy(
  //     msg.sender,
  //     delegateProxyImplementation,
  //     abi.encodeWithSignature('initialize(address,address)', msg.sender, address(this))
  //   );
  //   proxies[msg.sender] = proxy;
  //   return proxy;
  // }
}

contract TokenTransferProxy {
  /* Authentication registry. */
  ProxyRegistry public registry;

  /**
   * Call ERC20 `transferFrom`
   *
   * @dev Authenticated contract only
   * @param token ERC20 token address
   * @param from From address
   * @param to To address
   * @param amount Transfer amount
   */
  // function transferFrom(
  //   address token,
  //   address from,
  //   address to,
  //   uint256 amount
  // ) public returns (bool) {
  //   require(registry.contracts(msg.sender));
  //   return ERC20(token).transferFrom(from, to, amount);
  // }
}

contract WrapperWyvernExchange {
  using Address for address payable;
  using SafeERC20 for IERC20;

  // dummy vars for storage layout parity with wyvern
  bool reentrancyLock = false;
  address public storVar1;


  /* The token used to pay exchange fees. */
  ERC20 public exchangeToken;

  /* User registry. */
  ProxyRegistry public registry;

  /* Token transfer proxy. */
  TokenTransferProxy public tokenTransferProxy;

  /* Cancelled / finalized orders, by hash. */
  mapping(bytes32 => bool) public cancelledOrFinalized;

  /* Orders verified by on-chain approval (alternative to ECDSA signatures so that smart contracts can place orders directly). */
  mapping(bytes32 => bool) public approvedOrders;

  /* For split fee orders, minimum required protocol maker fee, in basis points. Paid to owner (who can change it). */
  uint256 public minimumMakerProtocolFee = 0;

  /* For split fee orders, minimum required protocol taker fee, in basis points. Paid to owner (who can change it). */
  uint256 public minimumTakerProtocolFee = 0;

  /* Recipient of protocol fees. */
  address public protocolFeeRecipient;

  /* Fee method: protocol fee or split fee. */
  enum FeeMethod {
    ProtocolFee,
    SplitFee
  }

  /* Inverse basis point. */
  uint256 public constant INVERSE_BASIS_POINT = 10000;

  string public constant name = 'Project Wyvern Exchange';

  string public constant version = '2.2';

  string public constant codename = 'Lambton Worm';

  IWyvernExchange public exchange;
  IRoyaltyEngine public engine;

  address payable public wallet;
  address public exchangeAddr;

  constructor(
    address _exchange,
    address _royaltyEngine,
    address _wallet
  ) {
    exchange = IWyvernExchange(_exchange);
    engine = IRoyaltyEngine(_royaltyEngine);
    wallet = payable(_wallet);
    exchangeAddr = _exchange;

    emit WalletUpdated(_wallet);
  }

  function atomicMatch_(
    address[14] memory addrs,
    uint256[18] memory uints,
    uint8[8] memory feeMethodsSidesKindsHowToCalls,
    bytes memory calldataBuy,
    bytes memory calldataSell,
    bytes memory replacementPatternBuy,
    bytes memory replacementPatternSell,
    bytes memory staticExtradataBuy,
    bytes memory staticExtradataSell,
    uint8[2] memory vs,
    bytes32[5] memory rssMetadata
  ) external payable {
    // 1. Perform exchange and forward any ETH
    // exchange.atomicMatch_{value: msg.value}(
    // addrs,
    // uints,
    // feeMethodsSidesKindsHowToCalls,
    // calldataBuy,
    // calldataSell,
    // replacementPatternBuy,
    // replacementPatternSell,
    // staticExtradataBuy,
    // staticExtradataSell,
    // vs,
    // rssMetadata
    // );

    exchangeAddr.delegatecall(
      abi.encodeWithSignature(
        'atomicMatch_(address[14],uint256[18],uint8[8],bytes,bytes,bytes,bytes,bytes,bytes,uint8[2],bytes32[5])',
        addrs,
        uints,
        feeMethodsSidesKindsHowToCalls,
        calldataBuy,
        calldataSell,
        replacementPatternBuy,
        replacementPatternSell,
        staticExtradataBuy,
        staticExtradataSell,
        vs,
        rssMetadata
      )
    );

    // 2. Validate fee parameters
    // require correct fee address, correct amount, royalty < 100% etc.

    // 3. Call the wallet hook to notify it that it's received a payment and that it should distribute a royalty
    //  wallet.processPayouts();
  }

  // Get royalty amounts from the registry
  function getRoyalty(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _value
  ) public view returns (address[] memory recipients, uint256[] memory amounts) {
    return engine.getRoyaltyView(_tokenAddress, _tokenId, _value);
  }

  // Where protocol fees are sent
  // function setWallet(address _wallet) external onlyOwner {
  //   wallet = payable(_wallet);
  //   emit WalletUpdated(_wallet);
  // }

  // Withdraw funds to wallet
  // function withdraw(address _token) external onlyOwner {
  //   uint256 balance;

  //   if (_token == address(0)) {
  //     // ETH withdrawal
  //     balance = address(this).balance;
  //     wallet.sendValue(balance);
  //   } else {
  //     // ERC20 withdrawal
  //     IERC20 token = IERC20(_token);
  //     balance = token.balanceOf(address(this));
  //     token.safeTransfer(wallet, balance);
  //   }

  //   emit Withdrawal(_token, wallet, balance);
  // }

  // function processPayouts() internal nonReentrant {
  //   // if 0 address eth payment, else token transfer
  //   // pay out royalties
  //   //
  // }

  event WalletUpdated(address _wallet);
  event FeeUpdated(uint256 _fee);
  event Withdrawal(address _token, address wallet, uint256 balance);
}
