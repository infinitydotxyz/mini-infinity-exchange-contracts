// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libs/Utils.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {ICurrencyRegistry} from '../interfaces/ICurrencyRegistry.sol';
import {IComplicationRegistry} from '../interfaces/IComplicationRegistry.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {IInfinityExchange} from '../interfaces/IInfinityExchange.sol';
import {INFTTransferManager} from '../interfaces/INFTTransferManager.sol';
import {INFTTransferSelector} from '../interfaces/INFTTransferSelector.sol';
import {IInfinityFeeDistributor} from '../interfaces/IInfinityFeeDistributor.sol';
import {SignatureChecker} from '../libs/SignatureChecker.sol';
import 'hardhat/console.sol'; // todo: remove this

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
  using OrderTypes for OrderTypes.Order;
  using OrderTypes for OrderTypes.Item;

  address public immutable WETH;
  bytes32 public immutable DOMAIN_SEPARATOR;

  ICurrencyRegistry public currencyRegistry;
  IComplicationRegistry public complicationRegistry;
  INFTTransferSelector public nftTransferSelector;
  IInfinityFeeDistributor public infinityFeeDistributor;

  mapping(address => uint256) public userMinOrderNonce;
  mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

  event CancelAllOrders(address indexed user, uint256 newMinNonce);
  event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
  event NewCurrencyRegistry(address indexed currencyRegistry);
  event NewComplicationRegistry(address indexed complicationRegistry);
  event NewNFTTransferSelector(address indexed nftTransferSelector);
  event NewInfinityFeeDistributor(address indexed infinityFeeDistributor);

  event OrderFulfilled(
    bytes32 sellOrderHash, // hash of the sell order
    bytes32 buyOrderHash, // hash of the sell order
    address indexed seller,
    address indexed buyer,
    address indexed complication, // address of the complication that defines the execution
    address currency, // token address of the transacting currency
    OrderTypes.Item[] items, // items sold; todo: check actual output
    uint256 amount // amount spent on the order
  );

  /**
   * @notice Constructor
   * @param _currencyRegistry currency manager address
   * @param _complicationRegistry execution manager address
   * @param _WETH wrapped ether address (for other chains, use wrapped native asset)
   */
  constructor(
    address _currencyRegistry,
    address _complicationRegistry,
    address _WETH
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

    currencyRegistry = ICurrencyRegistry(_currencyRegistry);
    complicationRegistry = IComplicationRegistry(_complicationRegistry);
    WETH = _WETH;
  }

  // =================================================== USER FUNCTIONS =======================================================

  /**
   * @notice Cancel all pending orders
   * @param minNonce minimum user nonce
   */
  function cancelAllOrders(uint256 minNonce) external {
    require(minNonce > userMinOrderNonce[msg.sender], 'Cancel: Nonce too low');
    require(minNonce < userMinOrderNonce[msg.sender] + 1000000, 'Cancel: Too many');
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
   * @notice Matches orders
   * @param sells sell orders
   * @param buys buy orders
   */
  function matchOrders(
    OrderTypes.Order[] calldata sells,
    OrderTypes.Order[] calldata buys,
    OrderTypes.Order[] calldata constructs
  ) external override nonReentrant {
    // check pre-conditions
    require(sells.length == buys.length, 'Match orders: mismatched lengths');
    require(sells.length == constructs.length, 'Match orders: mismatched lengths');
    // execute orders one by one
    for (uint256 i = 0; i < sells.length; ) {
      _matchOrders(sells[i], buys[i], constructs[i]);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Takes orders
   * @param makerOrders maker orders
   * @param takerOrders taker orders
   */
  function takeOrders(OrderTypes.Order[] calldata makerOrders, OrderTypes.Order[] calldata takerOrders)
    external
    override
    nonReentrant
  {
    // check pre-conditions
    require(makerOrders.length == takerOrders.length, 'Take Orders: mismatched lengths');
    // execute orders one by one
    for (uint256 i = 0; i < makerOrders.length; ) {
      _takeOrder(makerOrders[i], takerOrders[i]);
      unchecked {
        ++i;
      }
    }
  }

  // ====================================================== VIEW FUNCTIONS ======================================================

  /**
   * @notice Check whether user order nonce is executed or cancelled
   * @param user address of user
   * @param nonce nonce of the order
   */
  function isNonceValid(address user, uint256 nonce) external view returns (bool) {
    return !_isUserOrderNonceExecutedOrCancelled[user][nonce] && nonce > userMinOrderNonce[user];
  }

  function verifyOrderSig(OrderTypes.Order calldata order) external view returns (bool) {
    // Verify the validity of the signature
    (bytes32 r, bytes32 s, uint8 v) = abi.decode(order.sig, (bytes32, bytes32, uint8));
    return SignatureChecker.verify(order.hash(), order.signer, r, s, v, DOMAIN_SEPARATOR);
  }

  // ====================================================== INTERNAL FUNCTIONS ================================================

  function _matchOrders(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) internal {
    bytes32 sellOrderHash = sell.hash();
    bytes32 buyOrderHash = buy.hash();
    // if this order is not valid, just return and continue with other orders
    if (!_verifyOrders(sellOrderHash, buyOrderHash, sell, buy, constructed)) {
      return;
    }

    // exec order
    _execOrder(
      sellOrderHash,
      buyOrderHash,
      sell.signer,
      buy.signer,
      sell.constraints[6],
      buy.constraints[6],
      sell.constraints[5],
      constructed
    );
  }

  function _takeOrder(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder) internal {
    bytes32 makerOrderHash = makerOrder.hash();
    bytes32 takerOrderHash = takerOrder.hash();

    // if this order is not valid, just return and continue with other orders
    if (!_verifyTakeOrders(makerOrderHash, makerOrder, takerOrder)) {
      return;
    }

    // exec order
    bool isTakerSell = takerOrder.isSellOrder;
    if (isTakerSell) {
      _execOrder(
        takerOrderHash,
        makerOrderHash,
        takerOrder.signer,
        makerOrder.signer,
        takerOrder.constraints[6],
        makerOrder.constraints[6],
        takerOrder.constraints[5],
        takerOrder
      );
    } else {
      _execOrder(
        makerOrderHash,
        takerOrderHash,
        makerOrder.signer,
        takerOrder.signer,
        makerOrder.constraints[6],
        takerOrder.constraints[6],
        makerOrder.constraints[5],
        takerOrder
      );
    }
  }

  function _verifyOrders(
    bytes32 sellOrderHash,
    bytes32 buyOrderHash,
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) internal view returns (bool) {
    bool sidesMatch = sell.isSellOrder && !buy.isSellOrder;
    bool complicationsMatch = sell.execParams[0] == buy.execParams[0];
    bool currenciesMatch = sell.execParams[1] == buy.execParams[1];
    bool sellOrderValid = _isOrderValid(sell, sellOrderHash);
    bool buyOrderValid = _isOrderValid(buy, buyOrderHash);
    bool executionValid = IComplication(sell.execParams[0]).canExecOrder(sell, buy, constructed);
    return sidesMatch && complicationsMatch && currenciesMatch && sellOrderValid && buyOrderValid && executionValid;
  }

  function _verifyTakeOrders(
    bytes32 makerOrderHash,
    OrderTypes.Order calldata maker,
    OrderTypes.Order calldata taker
  ) internal view returns (bool) {
    bool msgSenderIsTaker = msg.sender == taker.signer;
    bool sidesMatch = (maker.isSellOrder && !taker.isSellOrder) || (!maker.isSellOrder && taker.isSellOrder);
    bool complicationsMatch = maker.execParams[0] == taker.execParams[0];
    bool currenciesMatch = maker.execParams[1] == taker.execParams[1];
    bool makerOrderValid = _isOrderValid(maker, makerOrderHash);
    bool executionValid = IComplication(maker.execParams[0]).canExecTakeOrder(maker, taker);
    return msgSenderIsTaker && sidesMatch && complicationsMatch && currenciesMatch && makerOrderValid && executionValid;
  }

  /**
   * @notice Verifies the validity of the order
   * @param order the order
   * @param orderHash computed hash of the order
   */
  function _isOrderValid(OrderTypes.Order calldata order, bytes32 orderHash) internal view returns (bool) {
    return
      _orderValidity(
        order.signer,
        order.sig,
        orderHash,
        order.execParams[0],
        order.execParams[1],
        order.constraints[6]
      );
  }

  function _orderValidity(
    address signer,
    bytes calldata sig,
    bytes32 orderHash,
    address complication,
    address currency,
    uint256 nonce
  ) internal view returns (bool) {
    bool orderExpired = _isUserOrderNonceExecutedOrCancelled[signer][nonce] || nonce < userMinOrderNonce[signer];
    // Verify the validity of the signature
    (uint8 v, bytes32 r, bytes32 s) = abi.decode(sig, (uint8, bytes32, bytes32));
    bool sigValid = SignatureChecker.verify(orderHash, signer, r, s, v, DOMAIN_SEPARATOR);

    if (
      orderExpired ||
      !sigValid ||
      signer == address(0) ||
      !currencyRegistry.isCurrencyWhitelisted(currency) ||
      !complicationRegistry.isComplicationWhitelisted(complication)
    ) {
      return false;
    }
    return true;
  }

  function _execOrder(
    bytes32 sellOrderHash,
    bytes32 buyOrderHash,
    address seller,
    address buyer,
    uint256 sellNonce,
    uint256 buyNonce,
    uint256 minBpsToSeller,
    OrderTypes.Order calldata constructed
  ) internal {
    // Update order execution status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[seller][sellNonce] = true;
    _isUserOrderNonceExecutedOrCancelled[buyer][buyNonce] = true;
    uint256 amount = Utils.getCurrentPrice(constructed);

    _transferNFTsAndFees(
      seller,
      buyer,
      constructed.nfts,
      amount,
      constructed.execParams[1],
      minBpsToSeller,
      constructed.execParams[0]
    );

    emit OrderFulfilled(
      sellOrderHash,
      buyOrderHash,
      seller,
      buyer,
      constructed.execParams[0],
      constructed.execParams[1],
      constructed.nfts,
      amount
    );
  }

  function _transferNFTsAndFees(
    address seller,
    address buyer,
    OrderTypes.Item[] calldata items,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address complication
  ) internal {
    uint256 numTokensToTransfer = 1; // assuming only ERC721
    for (uint256 i = 0; i < items.length; ) {
      OrderTypes.Item calldata item = items[i];
      address[] memory collections = new address[](1);
      collections[0] = item.collection;
      for (uint256 j = 0; j < item.tokenIds.length; ) {
        // transfer NFT
        _transferNFT(collections[0], seller, buyer, item.tokenIds[j], numTokensToTransfer);
        unchecked {
          ++j;
        }
      }
      // transfer fees
      _transferFees(seller, buyer, collections, item.tokenIds, amount, currency, minBpsToSeller, complication);
      unchecked {
        ++i;
      }
    }
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

  function _transferFees(
    address seller,
    address buyer,
    address[] memory collections,
    uint256[] memory tokenIds,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address complication
  ) internal {
    for (uint256 i = 0; i < collections.length; ) {
      address collection = collections[i];
      uint256 tokenId = tokenIds[i];
      // transfer fees
      infinityFeeDistributor.distributeFees(
        amount,
        currency,
        buyer,
        seller,
        minBpsToSeller,
        complication,
        collection,
        tokenId
      );
      unchecked {
        ++i;
      }
    }
  }

  // ====================================================== ADMIN FUNCTIONS ======================================================

  /**
   * @notice Update currency manager
   * @param _currencyRegistry new currency manager address
   */
  function updateCurrencyRegistry(address _currencyRegistry) external onlyOwner {
    require(_currencyRegistry != address(0), 'Owner: Cannot be 0x0');
    currencyRegistry = ICurrencyRegistry(_currencyRegistry);
    emit NewCurrencyRegistry(_currencyRegistry);
  }

  /**
   * @notice Update execution manager
   * @param _complicationRegistry new execution manager address
   */
  function updateComplicationRegistry(address _complicationRegistry) external onlyOwner {
    require(_complicationRegistry != address(0), 'Owner: Cannot be 0x0');
    complicationRegistry = IComplicationRegistry(_complicationRegistry);
    emit NewComplicationRegistry(_complicationRegistry);
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
}
