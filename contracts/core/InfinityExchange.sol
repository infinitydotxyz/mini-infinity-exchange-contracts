// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {ICurrencyRegistry} from '../interfaces/ICurrencyRegistry.sol';
import {IComplicationRegistry} from '../interfaces/IComplicationRegistry.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {IInfinityExchange} from '../interfaces/IInfinityExchange.sol';
import {IInfinityFeeTreasury} from '../interfaces/IInfinityFeeTreasury.sol';
import {IInfinityTradingRewards} from '../interfaces/IInfinityTradingRewards.sol';
import {SignatureChecker} from '../libs/SignatureChecker.sol';
import {IERC165} from '@openzeppelin/contracts/interfaces/IERC165.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
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
  using OrderTypes for OrderTypes.OrderItem;

  address public immutable WETH;
  bytes32 public immutable DOMAIN_SEPARATOR;

  ICurrencyRegistry public currencyRegistry;
  IComplicationRegistry public complicationRegistry;
  IInfinityFeeTreasury public infinityFeeTreasury;
  IInfinityTradingRewards public infinityTradingRewards;

  mapping(address => uint256) public userMinOrderNonce;
  mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

  event CancelAllOrders(address indexed user, uint256 newMinNonce);
  event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
  event NewCurrencyRegistry(address indexed currencyRegistry);
  event NewComplicationRegistry(address indexed complicationRegistry);
  event NewInfinityFeeTreasury(address indexed infinityFeeTreasury);

  event OrderFulfilled(
    bytes32 sellOrderHash, // hash of the sell order
    bytes32 buyOrderHash, // hash of the sell order
    address indexed seller,
    address indexed buyer,
    address indexed complication, // address of the complication that defines the execution
    address currency, // token address of the transacting currency
    OrderTypes.OrderItem[] nfts, // nfts sold; todo: check actual output
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
        keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
        keccak256('InfinityExchange'),
        keccak256(bytes('1')), // for versionId = 1
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

  function matchOrders(
    OrderTypes.Order[] calldata sells,
    OrderTypes.Order[] calldata buys,
    OrderTypes.Order[] calldata constructs,
    bool tradingRewards,
    bool feeDiscountEnabled
  ) external override nonReentrant {
    // check pre-conditions
    require(sells.length == buys.length, 'Match orders: mismatched lengths');
    require(sells.length == constructs.length, 'Match orders: mismatched lengths');

    if (tradingRewards) {
      address[] memory sellers;
      address[] memory buyers;
      address[] memory currencies;
      uint256[] memory amounts;
      // execute orders one by one
      for (uint256 i = 0; i < sells.length; ) {
        (sellers[i], buyers[i], currencies[i], amounts[i]) = _matchOrders(
          sells[i],
          buys[i],
          constructs[i],
          feeDiscountEnabled
        );
        unchecked {
          ++i;
        }
      }
      infinityTradingRewards.updateRewards(sellers, buyers, currencies, amounts);
    } else {
      for (uint256 i = 0; i < sells.length; ) {
        _matchOrders(sells[i], buys[i], constructs[i], feeDiscountEnabled);
        unchecked {
          ++i;
        }
      }
    }
  }

  function takeOrders(
    OrderTypes.Order[] calldata makerOrders,
    OrderTypes.Order[] calldata takerOrders,
    bool tradingRewards,
    bool feeDiscountEnabled
  ) external override nonReentrant {
    // check pre-conditions
    require(makerOrders.length == takerOrders.length, 'Take Orders: mismatched lengths');

    if (tradingRewards) {
      console.log('trading rewards enabled');
      address[] memory sellers;
      address[] memory buyers;
      address[] memory currencies;
      uint256[] memory amounts;
      // execute orders one by one
      for (uint256 i = 0; i < makerOrders.length; ) {
        (sellers[i], buyers[i], currencies[i], amounts[i]) = _takeOrders(
          makerOrders[i],
          takerOrders[i],
          feeDiscountEnabled
        );
        unchecked {
          ++i;
        }
      }
      infinityTradingRewards.updateRewards(sellers, buyers, currencies, amounts);
    } else {
      console.log('no trading rewards');
      for (uint256 i = 0; i < makerOrders.length; ) {
        _takeOrders(makerOrders[i], takerOrders[i], feeDiscountEnabled);
        unchecked {
          ++i;
        }
      }
    }
  }

  function batchTransferNFTs(
    address from,
    address to,
    OrderTypes.OrderItem[] calldata items
  ) external {
    _batchTransferNFTs(from, to, items);
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
    return SignatureChecker.verify(_hash(order), order.signer, r, s, v, DOMAIN_SEPARATOR);
  }

  // ====================================================== INTERNAL FUNCTIONS ================================================

  function _matchOrders(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    bytes32 sellOrderHash = _hash(sell);
    bytes32 buyOrderHash = _hash(buy);
    return _matchOrdersStackDeep(sellOrderHash, buyOrderHash, sell, buy, constructed, feeDiscountEnabled);
  }

  function _matchOrdersStackDeep(
    bytes32 sellOrderHash,
    bytes32 buyOrderHash,
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    // if this order is not valid, just return and continue with other orders
    if (!_verifyOrders(sellOrderHash, buyOrderHash, sell, buy, constructed)) {
      return (address(0), address(0), address(0), 0);
    }

    // exec order
    return
      _execOrder(
        sellOrderHash,
        buyOrderHash,
        sell.signer,
        buy.signer,
        sell.constraints[6],
        buy.constraints[6],
        sell.constraints[5],
        constructed,
        feeDiscountEnabled
      );
  }

  function _takeOrders(
    OrderTypes.Order calldata makerOrder,
    OrderTypes.Order calldata takerOrder,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    console.log('taking order');
    bytes32 makerOrderHash = _hash(makerOrder);
    bytes32 takerOrderHash = _hash(takerOrder);

    // if this order is not valid, just return and continue with other orders
    if (!_verifyTakeOrders(makerOrderHash, makerOrder, takerOrder)) {
      console.log('skipping invalid order');
      return (address(0), address(0), address(0), 0);
    }

    // exec order
    bool isTakerSell = takerOrder.isSellOrder;
    if (isTakerSell) {
      return _execTakerSellOrder(takerOrderHash, makerOrderHash, takerOrder, makerOrder, feeDiscountEnabled);
    } else {
      return _execTakerBuyOrder(takerOrderHash, makerOrderHash, takerOrder, makerOrder, feeDiscountEnabled);
    }
  }

  function _execTakerSellOrder(
    bytes32 takerOrderHash,
    bytes32 makerOrderHash,
    OrderTypes.Order calldata takerOrder,
    OrderTypes.Order calldata makerOrder,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    console.log('executing taker sell order');
    return
      _execOrder(
        takerOrderHash,
        makerOrderHash,
        takerOrder.signer,
        makerOrder.signer,
        takerOrder.constraints[6],
        makerOrder.constraints[6],
        takerOrder.constraints[5],
        takerOrder,
        feeDiscountEnabled
      );
  }

  function _execTakerBuyOrder(
    bytes32 takerOrderHash,
    bytes32 makerOrderHash,
    OrderTypes.Order calldata takerOrder,
    OrderTypes.Order calldata makerOrder,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    console.log('executing taker buy order');
    return
      _execOrder(
        makerOrderHash,
        takerOrderHash,
        makerOrder.signer,
        takerOrder.signer,
        makerOrder.constraints[6],
        takerOrder.constraints[6],
        makerOrder.constraints[5],
        takerOrder,
        feeDiscountEnabled
      );
  }

  function _verifyOrders(
    bytes32 sellOrderHash,
    bytes32 buyOrderHash,
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) internal view returns (bool) {
    console.log('verifying match orders');
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
    console.log('verifying take orders');
    bool msgSenderIsTaker = msg.sender == taker.signer;
    bool sidesMatch = (maker.isSellOrder && !taker.isSellOrder) || (!maker.isSellOrder && taker.isSellOrder);
    bool complicationsMatch = maker.execParams[0] == taker.execParams[0];
    bool currenciesMatch = maker.execParams[1] == taker.execParams[1];
    bool makerOrderValid = _isOrderValid(maker, makerOrderHash);
    bool executionValid = IComplication(maker.execParams[0]).canExecTakeOrder(maker, taker);
    console.log(msgSenderIsTaker);
    console.log(sidesMatch);
    console.log(complicationsMatch);
    console.log(currenciesMatch);
    console.log(makerOrderValid);
    console.log(executionValid);
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
    console.log('checking order validity');
    bool orderExpired = _isUserOrderNonceExecutedOrCancelled[signer][nonce] || nonce < userMinOrderNonce[signer];
    console.log('order expired:', orderExpired);
    // Verify the validity of the signature
    (bytes32 r, bytes32 s, uint8 v) = abi.decode(sig, (bytes32, bytes32, uint8));
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
    OrderTypes.Order calldata constructed,
    bool feeDiscountEnabled
  )
    internal
    returns (
      address,
      address,
      address,
      uint256
    )
  {
    console.log('executing order');
    uint256 amount = _getCurrentPrice(constructed);
    // Update order execution status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[seller][sellNonce] = true;
    _isUserOrderNonceExecutedOrCancelled[buyer][buyNonce] = true;

    _transferNFTsAndFees(
      seller,
      buyer,
      constructed.nfts,
      amount,
      constructed.execParams[1],
      minBpsToSeller,
      constructed.execParams[0],
      feeDiscountEnabled
    );

    _emitEvent(sellOrderHash, buyOrderHash, seller, buyer, constructed, amount);

    return (seller, buyer, constructed.execParams[1], amount);
  }

  function _getCurrentPrice(OrderTypes.Order calldata order) internal view returns (uint256) {
    (uint256 startPrice, uint256 endPrice) = (order.constraints[1], order.constraints[2]);
    (uint256 startTime, uint256 endTime) = (order.constraints[3], order.constraints[4]);
    uint256 duration = endTime - startTime;
    uint256 priceDiff = startPrice - endPrice;
    if (priceDiff == 0 || duration == 0) {
      return startPrice;
    }
    uint256 elapsedTime = block.timestamp - startTime;
    uint256 portion = elapsedTime > duration ? 1 : elapsedTime / duration;
    priceDiff = priceDiff * portion;
    return startPrice - priceDiff;
  }

  function _emitEvent(
    bytes32 sellOrderHash,
    bytes32 buyOrderHash,
    address seller,
    address buyer,
    OrderTypes.Order calldata constructed,
    uint256 amount
  ) internal {
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
    OrderTypes.OrderItem[] calldata nfts,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address complication,
    bool feeDiscountEnabled
  ) internal {
    console.log('transfering nfts and fees');
    // transfer NFTs
    _batchTransferNFTs(seller, buyer, nfts);
    // transfer fees
    _transferFees(seller, buyer, nfts, amount, currency, minBpsToSeller, complication, feeDiscountEnabled);
  }

  function _batchTransferNFTs(
    address from,
    address to,
    OrderTypes.OrderItem[] calldata nfts
  ) internal {
    console.log('batch transfering nfts');
    for (uint256 i = 0; i < nfts.length; ) {
      _transferNFTs(from, to, nfts[i]);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Transfer NFT
   * @param from address of the sender
   * @param to address of the recipient
   * @param item item to transfer
   */
  function _transferNFTs(
    address from,
    address to,
    OrderTypes.OrderItem calldata item
  ) internal {
    if (IERC165(item.collection).supportsInterface(0x80ac58cd)) {
      _transferERC721s(from, to, item);
    } else if (IERC165(item.collection).supportsInterface(0xd9b67a26)) {
      _transferERC1155s(from, to, item);
    }
  }

  function _transferERC721s(
    address from,
    address to,
    OrderTypes.OrderItem calldata item
  ) internal {
    for (uint256 i = 0; i < item.tokens.length; ) {
      console.log('transfering erc721 from collection', item.collection, 'with tokenId', item.tokens[i].tokenId);
      console.log('from address', from, 'to address', to);
      IERC721(item.collection).safeTransferFrom(from, to, item.tokens[i].tokenId);
      unchecked {
        ++i;
      }
    }
  }

  function _transferERC1155s(
    address from,
    address to,
    OrderTypes.OrderItem calldata item
  ) internal {
    for (uint256 i = 0; i < item.tokens.length; ) {
      console.log('transfering erc1155 from collection', item.collection, 'with tokenId', item.tokens[i].tokenId);
      console.log('num tokens', item.tokens[i].numTokens);
      console.log('from address', from, 'to address', to);
      IERC1155(item.collection).safeTransferFrom(from, to, item.tokens[i].tokenId, item.tokens[i].numTokens, '');
      unchecked {
        ++i;
      }
    }
  }

  function _transferFees(
    address seller,
    address buyer,
    OrderTypes.OrderItem[] calldata nfts,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address complication,
    bool feeDiscountEnabled
  ) internal {
    console.log('transfering fees');
    infinityFeeTreasury.allocateFees(
      seller,
      buyer,
      nfts,
      amount,
      currency,
      minBpsToSeller,
      complication,
      feeDiscountEnabled
    );
  }

  function _hash(OrderTypes.Order calldata order) internal pure returns (bytes32) {
    // keccak256("Order(bool isSellOrder,address signer,bytes32 dataHash,bytes extraParams)")
    bytes32 ORDER_HASH = 0x1bb57a2a1a64ebe03163e0964007805cfa2a9b6c0ee67005d6dcdd1bc46265dc;
    return
      keccak256(abi.encode(ORDER_HASH, order.isSellOrder, order.signer, order.dataHash, keccak256(order.extraParams)));
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
   * @notice Update fee distributor
   * @param _infinityFeeTreasury new address
   */
  function updateInfinityFeeTreasury(address _infinityFeeTreasury) external onlyOwner {
    require(_infinityFeeTreasury != address(0), 'Owner: Cannot be 0x0');
    infinityFeeTreasury = IInfinityFeeTreasury(_infinityFeeTreasury);
    emit NewInfinityFeeTreasury(_infinityFeeTreasury);
  }
}
