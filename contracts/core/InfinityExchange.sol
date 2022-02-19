// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {ICurrencyManager} from '../interfaces/ICurrencyManager.sol';
import {IExecutionManager} from '../interfaces/IExecutionManager.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {IInfinityExchange} from '../interfaces/IInfinityExchange.sol';
import {INFTTransferManager} from '../interfaces/INFTTransferManager.sol';
import {INFTTransferSelector} from '../interfaces/INFTTransferSelector.sol';
import {IInfinityFeeDistributor} from '../interfaces/IInfinityFeeDistributor.sol';
import {OrderTypes} from '../libraries/OrderTypes.sol';
import {SignatureChecker} from '../libraries/SignatureChecker.sol';

/**
 * @title InfinityExchange

NFTNFTNFT...........................................NFTNFTNFT
NFTNFT                                                 NFTNFT
NFT                                                       NFT
.                                                           .
.                                                           .
.                                                           .
.                                                           .
.               NFTNFTNFT            NFTNFTNFT              .
.            NFTNFTNFTNFTNFT      NFTNFTNFTNFTNFT           .
.           NFTNFTNFTNFTNFTNFT   NFTNFTNFTNFTNFTNFT         .
.         NFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFT        .
.         NFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFT        .
.         NFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFTNFT        .
.          NFTNFTNFTNFTNFTNFTN   NFTNFTNFTNFTNFTNFT         .
.            NFTNFTNFTNFTNFT      NFTNFTNFTNFTNFT           .
.               NFTNFTNFT            NFTNFTNFT              .
.                                                           .
.                                                           .
.                                                           .
.                                                           .
NFT                                                       NFT
NFTNFT                                                 NFTNFT
NFTNFTNFT...........................................NFTNFTNFT 

*/
contract InfinityExchange is IInfinityExchange, ReentrancyGuard, Ownable {
  using OrderTypes for OrderTypes.Maker;
  using OrderTypes for OrderTypes.Taker;

  address public immutable WETH;
  bytes32 public immutable DOMAIN_SEPARATOR;

  ICurrencyManager public currencyManager;
  IExecutionManager public executionManager;
  INFTTransferSelector public nftTransferSelector;
  IInfinityFeeDistributor public infinityFeeDistributor;

  mapping(address => uint256) public userMinOrderNonce;
  mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

  event CancelAllOrders(address indexed user, uint256 newMinNonce);
  event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
  event NewCurrencyManager(address indexed currencyManager);
  event NewExecutionManager(address indexed executionManager);
  event NewNFTTransferSelector(address indexed nftTransferSelector);
  event NewInfinityFeeDistributor(address indexed infinityFeeDistributor);

  event TakerSell(
    bytes32 orderHash, // buy hash of the maker order
    uint256 orderNonce, // user order nonce
    address indexed taker, // sender address for the taker sell order
    address indexed maker, // maker address of the initial buy order
    address indexed strategy, // strategy that defines the execution
    address currency, // currency address
    address collection, // collection address
    uint256 tokenId, // tokenId transferred
    uint256 amount, // amount of tokens transferred
    uint256 price // final transacted price
  );

  event TakerBuy(
    bytes32 orderHash, // sell hash of the maker order
    uint256 orderNonce, // user order nonce
    address indexed taker, // sender address for the taker buy order
    address indexed maker, // maker address of the initial sell order
    address indexed strategy, // strategy that defines the execution
    address currency, // currency address
    address collection, // collection address
    uint256 tokenId, // tokenId transferred
    uint256 amount, // amount of tokens transferred
    uint256 price // final transacted price
  );

  /**
   * @notice Constructor
   * @param _currencyManager currency manager address
   * @param _executionManager execution manager address
   * @param _WETH wrapped ether address (for other chains, use wrapped native asset)
   * @param _infinityFeeDistributor fee distributor address
   */
  constructor(
    address _currencyManager,
    address _executionManager,
    address _WETH,
    address _infinityFeeDistributor
  ) {
    // Calculate the domain separator
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        0xcd07a2d5dd0d50cbe9aef4d6509941c5576ea10e93ff919a6e4d463e00c5c9f8, // keccak256("InfinityExchange")
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1")) for versionId = 1
        block.chainid,
        address(this)
      )
    );

    currencyManager = ICurrencyManager(_currencyManager);
    executionManager = IExecutionManager(_executionManager);
    WETH = _WETH;
    infinityFeeDistributor = IInfinityFeeDistributor(_infinityFeeDistributor);
  }

  /**
   * @notice Cancel all pending orders for a sender
   * @param minNonce minimum user nonce
   */
  function cancelAllOrdersForSender(uint256 minNonce) external {
    require(minNonce > userMinOrderNonce[msg.sender], 'Cancel: Nonce too low');
    require(minNonce < userMinOrderNonce[msg.sender] + 500000, 'Cancel: Too many');
    userMinOrderNonce[msg.sender] = minNonce;

    emit CancelAllOrders(msg.sender, minNonce);
  }

  /**
   * @notice Cancel multiple orders
   * @param orderNonces array of order nonces
   */
  function cancelMultipleOrders(uint256[] calldata orderNonces) external {
    require(orderNonces.length > 0, 'Cancel: Cannot be empty');

    for (uint256 i = 0; i < orderNonces.length; i++) {
      require(orderNonces[i] >= userMinOrderNonce[msg.sender], 'Cancel: Nonce too low');
      _isUserOrderNonceExecutedOrCancelled[msg.sender][orderNonces[i]] = true;
    }

    emit CancelMultipleOrders(msg.sender, orderNonces);
  }

  /**
   * @notice Match takerBuys with matchSells
   * @param makerSells maker sell orders
   * @param takerBuys taker buy orders
   */
  function matchMakerSellsWithTakerBuys(OrderTypes.Maker[] calldata makerSells, OrderTypes.Taker[] calldata takerBuys)
    external
    override
    nonReentrant
  {
    // check pre-conditions
    require(makerSells.length == takerBuys.length, 'Order: Mismatched lengths');
    // execute orders one by one
    for (uint256 i = 0; i < makerSells.length; i++) {
      _matchMakerSellWithTakerBuy(makerSells[i], takerBuys[i]);
    }
  }

  function _matchMakerSellWithTakerBuy(OrderTypes.Maker calldata makerSell, OrderTypes.Taker calldata takerBuy)
    internal
  {
    (bool isSellOrder, address strategy, , uint256 nonce) = abi.decode(
      makerSell.execInfo,
      (bool, address, address, uint256)
    );
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == takerBuy.taker;

    // check if sides match
    bool sidesMatch = isSellOrder && !takerBuy.isSellOrder;

    // Check the maker sell order
    bytes32 sellHash = makerSell.hash();
    bool orderValid = _isOrderValid(makerSell, sellHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(strategy).canExecuteTakerBuy(
      takerBuy,
      makerSell
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this order is not valid, just return and continue with other orders
    if (!shouldExecute) {
      return;
    }

    // Update maker sell order status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[makerSell.signer][nonce] = true;

    // exec transfer
    _execTakerBuy(sellHash, makerSell, takerBuy, tokenId, amount);
  }

  function _execTakerBuy(
    bytes32 sellHash,
    OrderTypes.Maker calldata makerSell,
    OrderTypes.Taker calldata takerBuy,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address strategy, address currency, uint256 nonce) = abi.decode(
      makerSell.execInfo,
      (bool, address, address, uint256)
    );

    _transferFeesAndNFTs(false, makerSell, takerBuy, tokenId, amount);

    // emit event
    emit TakerBuy(
      sellHash,
      nonce,
      takerBuy.taker,
      makerSell.signer,
      strategy,
      currency,
      makerSell.collection,
      tokenId,
      amount,
      takerBuy.price
    );
  }

  /**
   * @notice Match a takerSell with a makerBuy
   * @param makerBuys maker buy order
   * @param takerSells taker sell order
   */
  function matchMakerBuysWithTakerSells(OrderTypes.Maker[] calldata makerBuys, OrderTypes.Taker[] calldata takerSells)
    external
    override
    nonReentrant
  {
    // check pre-conditions
    require(makerBuys.length == takerSells.length, 'Order: Mismatched lengths');

    // execute orders one by one
    for (uint256 i = 0; i < makerBuys.length; i++) {
      _matchMakerBuyWithTakerSell(makerBuys[i], takerSells[i]);
    }
  }

  function _matchMakerBuyWithTakerSell(OrderTypes.Maker calldata makerBuy, OrderTypes.Taker calldata takerSell)
    internal
  {
    (bool isSellOrder, address strategy, , uint256 nonce) = abi.decode(
      makerBuy.execInfo,
      (bool, address, address, uint256)
    );
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == takerSell.taker;

    // check if sides match
    bool sidesMatch = !isSellOrder && takerSell.isSellOrder;

    // Check the maker buy order
    bytes32 buyHash = makerBuy.hash();
    bool orderValid = _isOrderValid(makerBuy, buyHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(strategy).canExecuteTakerSell(
      takerSell,
      makerBuy
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this order is not valid, just return and continue with other orders
    if (!shouldExecute) {
      return;
    }

    // Update maker buy order status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[makerBuy.signer][nonce] = true;

    // exec transfer
    _execTakerSell(buyHash, makerBuy, takerSell, tokenId, amount);
  }

  function _execTakerSell(
    bytes32 buyHash,
    OrderTypes.Maker calldata makerBuy,
    OrderTypes.Taker calldata takerSell,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address strategy, address currency, uint256 nonce) = abi.decode(
      makerBuy.execInfo,
      (bool, address, address, uint256)
    );

    _transferFeesAndNFTs(true, makerBuy, takerSell, tokenId, amount);

    emit TakerSell(
      buyHash,
      nonce,
      takerSell.taker,
      makerBuy.signer,
      strategy,
      currency,
      makerBuy.collection,
      tokenId,
      amount,
      takerSell.price
    );
  }

  function _transferFeesAndNFTs(
    bool isSell,
    OrderTypes.Maker calldata maker,
    OrderTypes.Taker calldata taker,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address strategy, address currency, ) = abi.decode(maker.execInfo, (bool, address, address, uint256));
    (, , uint256 minBpsToSeller) = abi.decode(maker.prices, (uint256, uint256, uint256));

    if (isSell) {
      // transfer nfts
      _transferNFT(maker.collection, msg.sender, maker.signer, tokenId, amount);

      // distribute fees
      infinityFeeDistributor.distributeFees(
        strategy,
        taker.price,
        maker.collection,
        tokenId,
        currency,
        maker.signer,
        msg.sender,
        taker.minBpsToSeller
      );
    } else {
      // distribute fees
      infinityFeeDistributor.distributeFees(
        strategy,
        taker.price,
        maker.collection,
        tokenId,
        currency,
        msg.sender,
        maker.signer,
        minBpsToSeller
      );

      // transfer nfts
      _transferNFT(maker.collection, maker.signer, taker.taker, tokenId, amount);
    }
  }

  /**
   * @notice Update currency manager
   * @param _currencyManager new currency manager address
   */
  function updateCurrencyManager(address _currencyManager) external onlyOwner {
    require(_currencyManager != address(0), 'Owner: Cannot be 0x0');
    currencyManager = ICurrencyManager(_currencyManager);
    emit NewCurrencyManager(_currencyManager);
  }

  /**
   * @notice Update execution manager
   * @param _executionManager new execution manager address
   */
  function updateExecutionManager(address _executionManager) external onlyOwner {
    require(_executionManager != address(0), 'Owner: Cannot be 0x0');
    executionManager = IExecutionManager(_executionManager);
    emit NewExecutionManager(_executionManager);
  }

  /**
   * @notice Update transfer selector NFT
   * @param _nftTransferSelector new transfer selector address
   */
  function updateNFTTransferSelector(address _nftTransferSelector) external onlyOwner {
    require(_nftTransferSelector != address(0), 'Owner: Cannot be 0x0');
    nftTransferSelector = INFTTransferSelector(_nftTransferSelector);

    emit NewNFTTransferSelector(_nftTransferSelector);
  }

  /**
   * @notice Update fee distributor
   * @param _infinityFeeDistributor new infinityFeeDistributor address
   */
  function updateInfinityFeeDistributor(address _infinityFeeDistributor) external onlyOwner {
    require(_infinityFeeDistributor != address(0), 'Owner: Cannot be 0x0');
    infinityFeeDistributor = IInfinityFeeDistributor(_infinityFeeDistributor);

    emit NewInfinityFeeDistributor(_infinityFeeDistributor);
  }

  /**
   * @notice Check whether user order nonce is executed or cancelled
   * @param user address of user
   * @param orderNonce nonce of the order
   */
  function isUserOrderNonceExecutedOrCancelled(address user, uint256 orderNonce) external view returns (bool) {
    return _isUserOrderNonceExecutedOrCancelled[user][orderNonce];
  }

  /**
   * @notice Transfer NFT
   * @param collection address of the token collection
   * @param from address of the sender
   * @param to address of the recipient
   * @param tokenId tokenId
   * @param amount amount of tokens (1 for ERC721, 1+ for ERC1155)
   * @dev For ERC721, amount is not used
   */
  function _transferNFT(
    address collection,
    address from,
    address to,
    uint256 tokenId,
    uint256 amount
  ) internal {
    // Retrieve the transfer manager address
    address transferManager = nftTransferSelector.getTransferManager(collection);

    // If no transfer manager found, it returns address(0)
    require(transferManager != address(0), 'Transfer: No NFT transfer manager available');

    // If one is found, transfer the token
    INFTTransferManager(transferManager).transferNFT(collection, from, to, tokenId, amount);
  }

  /**
   * @notice Verify the validity of the maker order
   * @param makerOrder maker order
   * @param orderHash computed hash for the order
   */
  function _isOrderValid(OrderTypes.Maker calldata makerOrder, bytes32 orderHash) internal view returns (bool) {
    // Verify whether order nonce has expired
    (, address strategy, address currency, uint256 nonce) = abi.decode(
      makerOrder.execInfo,
      (bool, address, address, uint256)
    );
    (, uint256 amount) = abi.decode(makerOrder.tokenInfo, (uint256, uint256));

    bool orderExpired = _isUserOrderNonceExecutedOrCancelled[makerOrder.signer][nonce] ||
      nonce < userMinOrderNonce[makerOrder.signer];

    // Verify the validity of the signature
    (uint8 v, bytes32 r, bytes32 s) = abi.decode(makerOrder.sig, (uint8, bytes32, bytes32));
    bool sigValid = SignatureChecker.verify(orderHash, makerOrder.signer, v, r, s, DOMAIN_SEPARATOR);

    if (
      orderExpired ||
      !sigValid ||
      makerOrder.signer == address(0) ||
      amount == 0 ||
      !currencyManager.isCurrencyWhitelisted(currency) ||
      !executionManager.isStrategyWhitelisted(strategy)
    ) {
      return false;
    }
    return true;
  }
}
