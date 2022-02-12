// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

// interfaces
import {ICurrencyManager} from '../interfaces/ICurrencyManager.sol';
import {IExecutionManager} from '../interfaces/IExecutionManager.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {IRoyaltyFeeManager} from '../interfaces/IRoyaltyFeeManager.sol';
import {IInfinityExchange} from '../interfaces/IInfinityExchange.sol';
import {ITransferManagerNFT} from '../interfaces/ITransferManagerNFT.sol';
import {ITransferSelectorNFT} from '../interfaces/ITransferSelectorNFT.sol';
import {IWETH} from '../interfaces/IWETH.sol';

// libraries
import {OrderTypes} from '../libraries/OrderTypes.sol';
import {SignatureChecker} from '../libraries/SignatureChecker.sol';

/**
 * @title InfinityExchange
 * @notice Core exchange contract

MMMWXkl,..                                        .';oONMMMM
MWKl'                                                 .,xXMM
Nx'                                                      ;OW
d.                                                        'O
.                                                          :
                                                           .
                                                           .
                                                           .
                                                           .
              .,coodooc,.          .;coddol:'.             .
            ,dKNWMMMMMWN0o'      ;xKWWMMMMMWNOl.           .
          .dXMMMMMMMMMMMMWKc.  .dNMMMMMMMMMMMMWKc.         .
         .xWMMMMMMMMMMMMMMMXl':xWMMMMMMMMMMMMMMMXl         .
         :XMMMMMMMMMMMMMMMMMK0XWMMMMMMMMMMMMMMMMMO.        .
         cXMMMMMMMMMMMMMMMMMNNWMMMMMMMMMMMMMMMMMMO'        .
         ,OMMMMMMMMMMMMMMMMWxld0MMMMMMMMMMMMMMMMWd.        .
          :0WMMMMMMMMMMMMMWx. .;0WMMMMMMMMMMMMMNx'         .
           'oKWMMMMMMMMMW0c.    'dXWMMMMMMMMMNOc.          .
             .:ok0KXK0ko:.        'cdO0KKK0xl;.            .
                 .....                .....                .
                                                           .
                                                           .
                                                           .
.                                                          ,
;                                                         .o
0;                                                       .lX
MXo.                                                    ,xNM
MMWKd;.                                              .:kXMMM
MMMMMNOl,.                                       ..;o0WMMMMM

*/
contract InfinityExchange is IInfinityExchange, ReentrancyGuard, Ownable {
  using SafeERC20 for IERC20;

  using OrderTypes for OrderTypes.MakerOrder;
  using OrderTypes for OrderTypes.TakerOrder;

  address public immutable WETH;
  bytes32 public immutable DOMAIN_SEPARATOR;

  address public protocolFeeRecipient;

  ICurrencyManager public currencyManager;
  IExecutionManager public executionManager;
  IRoyaltyFeeManager public royaltyFeeManager;
  ITransferSelectorNFT public transferSelectorNFT;

  mapping(address => uint256) public userMinOrderNonce;
  mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

  event CancelAllOrders(address indexed user, uint256 newMinNonce);
  event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
  event NewCurrencyManager(address indexed currencyManager);
  event NewExecutionManager(address indexed executionManager);
  event NewProtocolFeeRecipient(address indexed protocolFeeRecipient);
  event NewRoyaltyFeeManager(address indexed royaltyFeeManager);
  event NewTransferSelectorNFT(address indexed transferSelectorNFT);

  event RoyaltyPayment(
    address indexed collection,
    uint256 indexed tokenId,
    address indexed royaltyRecipient,
    address currency,
    uint256 amount
  );

  event TakerAsk(
    bytes32 orderHash, // bid hash of the maker order
    uint256 orderNonce, // user order nonce
    address indexed taker, // sender address for the taker ask order
    address indexed maker, // maker address of the initial bid order
    address indexed strategy, // strategy that defines the execution
    address currency, // currency address
    address collection, // collection address
    uint256 tokenId, // tokenId transferred
    uint256 amount, // amount of tokens transferred
    uint256 price // final transacted price
  );

  event TakerBid(
    bytes32 orderHash, // ask hash of the maker order
    uint256 orderNonce, // user order nonce
    address indexed taker, // sender address for the taker bid order
    address indexed maker, // maker address of the initial ask order
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
   * @param _royaltyFeeManager royalty fee manager address
   * @param _WETH wrapped ether address (for other chains, use wrapped native asset)
   * @param _protocolFeeRecipient protocol fee recipient
   */
  constructor(
    address _currencyManager,
    address _executionManager,
    address _royaltyFeeManager,
    address _WETH,
    address _protocolFeeRecipient
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
    royaltyFeeManager = IRoyaltyFeeManager(_royaltyFeeManager);
    WETH = _WETH;
    protocolFeeRecipient = _protocolFeeRecipient;
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
   * @notice Match takerBids with matchAsks
   * @param makerAsks maker ask orders
   * @param takerBids taker bid orders
   */
  function matchMakerAsksWithTakerBids(
    OrderTypes.MakerOrder[] calldata makerAsks,
    OrderTypes.TakerOrder[] calldata takerBids
  ) external override nonReentrant {
    // check pre-conditions
    require(makerAsks.length == takerBids.length, 'Order: Mismatched lengths');
    // execute orders one by one
    for (uint256 i = 0; i < makerAsks.length; i++) {
      _matchMakerAskWithTakerBid(makerAsks[i], takerBids[i]);
    }
  }

  function _matchMakerAskWithTakerBid(OrderTypes.MakerOrder calldata makerAsk, OrderTypes.TakerOrder calldata takerBid)
    internal
  {
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == takerBid.taker;

    // check if sides match
    bool sidesMatch = makerAsk.isOrderAsk && !takerBid.isOrderAsk;

    // Check the maker ask order
    bytes32 askHash = makerAsk.hash();
    bool orderValid = _isOrderValid(makerAsk, askHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(makerAsk.strategy).canExecuteTakerBid(
      takerBid,
      makerAsk
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this order is not valid, just return and continue with other orders
    if (!shouldExecute) {
      return;
    }

    // Update maker ask order status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[makerAsk.signer][makerAsk.nonce] = true;

    // exec transfer
    _execTakerBid(askHash, makerAsk, takerBid, tokenId, amount);
  }

  function _execTakerBid(
    bytes32 askHash,
    OrderTypes.MakerOrder calldata makerAsk,
    OrderTypes.TakerOrder calldata takerBid,
    uint256 tokenId,
    uint256 amount
  ) internal {
    _transferFeesAndFunds(
      makerAsk.strategy,
      makerAsk.collection,
      tokenId,
      makerAsk.currency,
      msg.sender,
      makerAsk.signer,
      takerBid.price,
      makerAsk.minPercentageToAsk
    );

    // Execution part 2/2
    _transferNonFungibleToken(makerAsk.collection, makerAsk.signer, takerBid.taker, tokenId, amount);

    // emit event
    emit TakerBid(
      askHash,
      makerAsk.nonce,
      takerBid.taker,
      makerAsk.signer,
      makerAsk.strategy,
      makerAsk.currency,
      makerAsk.collection,
      tokenId,
      amount,
      takerBid.price
    );
  }

  /**
   * @notice Match a takerAsk with a makerBid
   * @param makerBids maker bid order
   * @param takerAsks taker ask order
   */
  function matchMakerBidsWithTakerAsks(
    OrderTypes.MakerOrder[] calldata makerBids,
    OrderTypes.TakerOrder[] calldata takerAsks
  ) external override nonReentrant {
    // check pre-conditions
    require(makerBids.length == takerAsks.length, 'Order: Mismatched lengths');

    // execute orders one by one
    for (uint256 i = 0; i < makerBids.length; i++) {
      _matchMakerBidWithTakerAsk(makerBids[i], takerAsks[i]);
    }
  }

  function _matchMakerBidWithTakerAsk(OrderTypes.MakerOrder calldata makerBid, OrderTypes.TakerOrder calldata takerAsk)
    internal
  {
    // check if msg sender is taker
    bool msgSenderIsTaker = msg.sender == takerAsk.taker;

    // check if sides match
    bool sidesMatch = !makerBid.isOrderAsk && takerAsk.isOrderAsk;

    // Check the maker bid order
    bytes32 bidHash = makerBid.hash();
    bool orderValid = _isOrderValid(makerBid, bidHash);

    // check if execution is valid
    (bool executionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(makerBid.strategy).canExecuteTakerAsk(
      takerAsk,
      makerBid
    );

    bool shouldExecute = msgSenderIsTaker && sidesMatch && orderValid && executionValid;

    // if this order is not valid, just return and continue with other orders
    if (!shouldExecute) {
      return;
    }

    // Update maker bid order status to true (prevents replay)
    _isUserOrderNonceExecutedOrCancelled[makerBid.signer][makerBid.nonce] = true;

    // exec transfer
    _execTakerAsk(bidHash, makerBid, takerAsk, tokenId, amount);
  }

  function _execTakerAsk(
    bytes32 bidHash,
    OrderTypes.MakerOrder calldata makerBid,
    OrderTypes.TakerOrder calldata takerAsk,
    uint256 tokenId,
    uint256 amount
  ) internal {
    // Execution part 1/2
    _transferNonFungibleToken(makerBid.collection, msg.sender, makerBid.signer, tokenId, amount);

    // Execution part 2/2
    _transferFeesAndFunds(
      makerBid.strategy,
      makerBid.collection,
      tokenId,
      makerBid.currency,
      makerBid.signer,
      msg.sender,
      takerAsk.price,
      takerAsk.minPercentageToAsk
    );

    emit TakerAsk(
      bidHash,
      makerBid.nonce,
      takerAsk.taker,
      makerBid.signer,
      makerBid.strategy,
      makerBid.currency,
      makerBid.collection,
      tokenId,
      amount,
      takerAsk.price
    );
  }

  /**
   * @notice Update currency manager
   * @param _currencyManager new currency manager address
   */
  function updateCurrencyManager(address _currencyManager) external onlyOwner {
    require(_currencyManager != address(0), 'Owner: Cannot be null address');
    currencyManager = ICurrencyManager(_currencyManager);
    emit NewCurrencyManager(_currencyManager);
  }

  /**
   * @notice Update execution manager
   * @param _executionManager new execution manager address
   */
  function updateExecutionManager(address _executionManager) external onlyOwner {
    require(_executionManager != address(0), 'Owner: Cannot be null address');
    executionManager = IExecutionManager(_executionManager);
    emit NewExecutionManager(_executionManager);
  }

  /**
   * @notice Update protocol fee and recipient
   * @param _protocolFeeRecipient new recipient for protocol fees
   */
  function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
    protocolFeeRecipient = _protocolFeeRecipient;
    emit NewProtocolFeeRecipient(_protocolFeeRecipient);
  }

  /**
   * @notice Update royalty fee manager
   * @param _royaltyFeeManager new fee manager address
   */
  function updateRoyaltyFeeManager(address _royaltyFeeManager) external onlyOwner {
    require(_royaltyFeeManager != address(0), 'Owner: Cannot be null address');
    royaltyFeeManager = IRoyaltyFeeManager(_royaltyFeeManager);
    emit NewRoyaltyFeeManager(_royaltyFeeManager);
  }

  /**
   * @notice Update transfer selector NFT
   * @param _transferSelectorNFT new transfer selector address
   */
  function updateTransferSelectorNFT(address _transferSelectorNFT) external onlyOwner {
    require(_transferSelectorNFT != address(0), 'Owner: Cannot be null address');
    transferSelectorNFT = ITransferSelectorNFT(_transferSelectorNFT);

    emit NewTransferSelectorNFT(_transferSelectorNFT);
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
   * @notice Transfer fees and funds to royalty recipient, protocol, and seller
   * @param strategy address of the execution strategy
   * @param collection non fungible token address for the transfer
   * @param tokenId tokenId
   * @param currency currency being used for the purchase (e.g., WETH/USDC)
   * @param from sender of the funds
   * @param to seller's recipient
   * @param amount amount being transferred (in currency)
   * @param minPercentageToAsk minimum percentage of the gross amount that goes to ask
   */
  function _transferFeesAndFunds(
    address strategy,
    address collection,
    uint256 tokenId,
    address currency,
    address from,
    address to,
    uint256 amount,
    uint256 minPercentageToAsk
  ) internal {
    // Initialize the final amount that is transferred to seller
    uint256 finalSellerAmount = amount;

    // 1. Protocol fee
    uint256 protocolFeeAmount = _calculateProtocolFee(strategy, amount);

    // Check if the protocol fee is different than 0 for this strategy
    if ((protocolFeeRecipient != address(0)) && (protocolFeeAmount != 0)) {
      IERC20(currency).safeTransferFrom(from, protocolFeeRecipient, protocolFeeAmount);
      finalSellerAmount -= protocolFeeAmount;
    }

    // 2. Royalty fees
    (address[] memory royaltyFeeRecipients, uint256[] memory royaltyFeeAmounts) = royaltyFeeManager
      .calculateRoyaltyFeesAndGetRecipients(collection, tokenId, amount);

    // send royalties
    uint256 numRecipients = royaltyFeeRecipients.length;
    for (uint256 i = 0; i < numRecipients; i++) {
      if (royaltyFeeRecipients[i] != address(0) && royaltyFeeAmounts[i] != 0) {
        IERC20(currency).safeTransferFrom(from, royaltyFeeRecipients[i], royaltyFeeAmounts[i]);
        finalSellerAmount -= royaltyFeeAmounts[i];

        emit RoyaltyPayment(collection, tokenId, royaltyFeeRecipients[i], currency, royaltyFeeAmounts[i]);
      }
    }

    // check min ask is met
    require((finalSellerAmount * 10000) >= (minPercentageToAsk * amount), 'Fees: Higher than expected');

    // 3. Transfer final amount (post-fees) to seller
    IERC20(currency).safeTransferFrom(from, to, finalSellerAmount);
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
  function _transferNonFungibleToken(
    address collection,
    address from,
    address to,
    uint256 tokenId,
    uint256 amount
  ) internal {
    // Retrieve the transfer manager address
    address transferManager = transferSelectorNFT.checkTransferManagerForToken(collection);

    // If no transfer manager found, it returns address(0)
    require(transferManager != address(0), 'Transfer: No NFT transfer manager available');

    // If one is found, transfer the token
    ITransferManagerNFT(transferManager).transferNonFungibleToken(collection, from, to, tokenId, amount);
  }

  /**
   * @notice Calculate protocol fee for an execution strategy
   * @param executionStrategy strategy
   * @param amount amount to transfer
   */
  function _calculateProtocolFee(address executionStrategy, uint256 amount) internal view returns (uint256) {
    uint256 protocolFee = IExecutionStrategy(executionStrategy).viewProtocolFee();
    return (protocolFee * amount) / 10000;
  }

  /**
   * @notice Verify the validity of the maker order
   * @param makerOrder maker order
   * @param orderHash computed hash for the order
   */
  function _isOrderValid(OrderTypes.MakerOrder calldata makerOrder, bytes32 orderHash) internal view returns (bool) {
    // Verify whether order nonce has expired
    bool orderExpired = _isUserOrderNonceExecutedOrCancelled[makerOrder.signer][makerOrder.nonce] ||
      makerOrder.nonce < userMinOrderNonce[makerOrder.signer];

    // Verify the validity of the signature
    (uint8 v, bytes32 r, bytes32 s) = abi.decode(makerOrder.sig, (uint8, bytes32, bytes32));
    bool sigValid = SignatureChecker.verify(orderHash, makerOrder.signer, v, r, s, DOMAIN_SEPARATOR);

    if (
      orderExpired ||
      !sigValid ||
      makerOrder.signer == address(0) ||
      makerOrder.amount == 0 ||
      !currencyManager.isCurrencyWhitelisted(makerOrder.currency) ||
      !executionManager.isStrategyWhitelisted(makerOrder.strategy)
    ) {
      return false;
    }
    return true;
  }
}
