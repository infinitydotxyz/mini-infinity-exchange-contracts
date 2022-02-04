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

contract WrapperWyvernExchange is Ownable, ReentrancyGuard {
  using Address for address payable;
  using SafeERC20 for IERC20;

  IWyvernExchange public exchange;
  IRoyaltyEngine public engine;

  address payable public wallet;

  constructor(
    address _exchange,
    address _royaltyEngine,
    address _wallet
  ) {
    exchange = IWyvernExchange(_exchange);
    engine = IRoyaltyEngine(_royaltyEngine);
    wallet = payable(_wallet);

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
    exchange.atomicMatch_{value: msg.value}(
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
  function setWallet(address _wallet) external onlyOwner {
    wallet = payable(_wallet);
    emit WalletUpdated(_wallet);
  }

  // Withdraw funds to wallet
  function withdraw(address _token) external onlyOwner {
    uint256 balance;

    if (_token == address(0)) {
      // ETH withdrawal
      balance = address(this).balance;
      wallet.sendValue(balance);
    } else {
      // ERC20 withdrawal
      IERC20 token = IERC20(_token);
      balance = token.balanceOf(address(this));
      token.safeTransfer(wallet, balance);
    }

    emit Withdrawal(_token, wallet, balance);
  }

  function processPayouts() internal nonReentrant {
    // if 0 address eth payment, else token transfer
    // pay out royalties
    //
  }

  event WalletUpdated(address _wallet);
  event FeeUpdated(uint256 _fee);
  event Withdrawal(address _token, address wallet, uint256 balance);
}
