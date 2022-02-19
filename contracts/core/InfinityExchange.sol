// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {ICurrencyManager} from '../interfaces/ICurrencyManager.sol';
import {IExecutionStrategyRegistry} from '../interfaces/IExecutionStrategyRegistry.sol';
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
  IExecutionStrategyRegistry public executionStrategyRegistry;
  INFTTransferSelector public nftTransferSelector;
  IInfinityFeeDistributor public infinityFeeDistributor;

  mapping(address => uint256) public userMinOrderNonce;
  mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

  event CancelAllOrders(address indexed user, uint256 newMinNonce);
  event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
  event NewCurrencyManager(address indexed currencyManager);
  event NewExecutionStrategyRegistry(address indexed executionStrategyRegistry);
  event NewNFTTransferSelector(address indexed nftTransferSelector);
  event NewInfinityFeeDistributor(address indexed infinityFeeDistributor);

  event OrderFulfilled(
    string orderType,
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

  /**
   * @notice Constructor
   * @param _currencyManager currency manager address
   * @param _executionStrategyRegistry execution manager address
   * @param _WETH wrapped ether address (for other chains, use wrapped native asset)
   */
  constructor(
    address _currencyManager,
    address _executionStrategyRegistry,
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

    currencyManager = ICurrencyManager(_currencyManager);
    executionStrategyRegistry = IExecutionStrategyRegistry(_executionStrategyRegistry);
    WETH = _WETH;
  }

  /**
   * @notice Cancel all pending orders for a sender
   * @param minNonce minimum user nonce
   */
  function cancelAllOrdersForSender(uint256 minNonce) external {
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
   * @notice Match listings with buy orders
   * @param listings maker listings
   * @param buys taker buy orders
   */
  function matchListingsWithBuys(OrderTypes.Maker[] calldata listings, OrderTypes.Taker[] calldata buys)
    external
    override
    nonReentrant
  {
    // check pre-conditions
    require(listings.length == buys.length, 'Order: Mismatched lengths');
    // execute orders one by one
    for (uint256 i = 0; i < listings.length; i++) {
      _matchListingWithBuy(listings[i], buys[i]);
    }
  }

  function _matchListingWithBuy(OrderTypes.Maker calldata listing, OrderTypes.Taker calldata buy) internal {
    (bool isListing, address strategy, , uint256 nonce) = abi.decode(
      listing.execInfo,
      (bool, address, address, uint256)
    );
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == buy.taker;

    // check if sides match
    bool sidesMatch = isListing && !buy.isSellOrder;

    // check if listing is valid
    bytes32 listingHash = listing.hash();
    bool orderValid = _isOrderValid(listing, listingHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(strategy).canExecuteListing(
      buy,
      listing
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this listing is not valid, just return and continue with other listings
    if (!shouldExecute) {
      return;
    }

    // Update listing execution status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[listing.signer][nonce] = true;

    // exec listing
    _execListing(listingHash, listing, buy, tokenId, amount);
  }

  function _execListing(
    bytes32 listingHash,
    OrderTypes.Maker calldata listing,
    OrderTypes.Taker calldata buy,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address strategy, address currency, uint256 nonce) = abi.decode(
      listing.execInfo,
      (bool, address, address, uint256)
    );

    _transferFeesAndNFTs(false, listing, buy, tokenId, amount);

    // emit event
    emit OrderFulfilled(
      'Listing',
      listingHash,
      nonce,
      buy.taker,
      listing.signer,
      strategy,
      currency,
      listing.collection,
      tokenId,
      amount,
      buy.price
    );
  }

  /**
   * @notice Match a offers with accepts
   * @param offers maker offers
   * @param accepts taker accepts
   */
  function matchOffersWithAccepts(OrderTypes.Maker[] calldata offers, OrderTypes.Taker[] calldata accepts)
    external
    override
    nonReentrant
  {
    // check pre-conditions
    require(offers.length == accepts.length, 'Order: Mismatched lengths');

    // execute orders one by one
    for (uint256 i = 0; i < offers.length; i++) {
      _matchOfferWithAccept(offers[i], accepts[i]);
    }
  }

  function _matchOfferWithAccept(OrderTypes.Maker calldata offer, OrderTypes.Taker calldata accept) internal {
    (bool isListing, address strategy, , uint256 nonce) = abi.decode(offer.execInfo, (bool, address, address, uint256));
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == accept.taker;

    // check if sides match
    bool sidesMatch = !isListing && accept.isSellOrder;

    // Check if offer is valid
    bytes32 offerHash = offer.hash();
    bool orderValid = _isOrderValid(offer, offerHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(strategy).canExecuteOffer(
      accept,
      offer
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this offer is not valid, just return and continue with other offers
    if (!shouldExecute) {
      return;
    }

    // Update maker buy order status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[offer.signer][nonce] = true;

    // exec offer
    _execOffer(offerHash, offer, accept, tokenId, amount);
  }

  function _execOffer(
    bytes32 offerHash,
    OrderTypes.Maker calldata offer,
    OrderTypes.Taker calldata accept,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address strategy, address currency, uint256 nonce) = abi.decode(
      offer.execInfo,
      (bool, address, address, uint256)
    );

    _transferFeesAndNFTs(true, offer, accept, tokenId, amount);

    emit OrderFulfilled(
      'Offer',
      offerHash,
      nonce,
      accept.taker,
      offer.signer,
      strategy,
      currency,
      offer.collection,
      tokenId,
      amount,
      accept.price
    );
  }

  function _transferFeesAndNFTs(
    bool isAcceptOffer,
    OrderTypes.Maker calldata maker,
    OrderTypes.Taker calldata taker,
    uint256 tokenId,
    uint256 amount
  ) internal {
    (, address execStrategy, address currency, ) = abi.decode(maker.execInfo, (bool, address, address, uint256));
    (, , uint256 minBpsToSeller) = abi.decode(maker.prices, (uint256, uint256, uint256));

    if (isAcceptOffer) {
      _transferNFT(maker.collection, msg.sender, maker.signer, tokenId, amount);

      infinityFeeDistributor.distributeFees(
        taker.price,
        currency,
        maker.signer,
        msg.sender,
        taker.minBpsToSeller,
        execStrategy,
        maker.collection,
        tokenId
      );
    } else {
      infinityFeeDistributor.distributeFees(
        taker.price,
        currency,
        msg.sender,
        maker.signer,
        minBpsToSeller,
        execStrategy,
        maker.collection,
        tokenId
      );

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
   * @param _executionStrategyRegistry new execution manager address
   */
  function updateExecutionStrategyRegistry(address _executionStrategyRegistry) external onlyOwner {
    require(_executionStrategyRegistry != address(0), 'Owner: Cannot be 0x0');
    executionStrategyRegistry = IExecutionStrategyRegistry(_executionStrategyRegistry);
    emit NewExecutionStrategyRegistry(_executionStrategyRegistry);
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
      !executionStrategyRegistry.isStrategyWhitelisted(strategy)
    ) {
      return false;
    }
    return true;
  }
}
