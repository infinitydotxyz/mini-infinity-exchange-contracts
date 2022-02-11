// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OrderTypes
 * @notice This library contains order types for the Infinity exchange.
 */
library OrderTypes {
  // keccak256("MakerOrder(bool isOrderAsk,address signer,address collection,bytes prices,uint256 tokenId,uint256 amount,address strategy,address currency,uint256 nonce,bytes startAndEndTimes,uint256 minPercentageToAsk,bytes params)")
  bytes32 internal constant MAKER_ORDER_HASH = 0x95467f11fc00c60725229bb6eb4761e8cf0e9d8ed0704f18395b5065a8bef5f1;

  struct MakerOrder {
    bool isOrderAsk; // true --> ask / false --> bid
    address signer; // signer of the maker order
    address collection; // collection address
    bytes prices; // startPrice and endPrice
    uint256 tokenId; // id of the token
    uint256 amount; // amount of tokens to sell/purchase (must be 1 for ERC721, 1+ for ERC1155)
    address strategy; // strategy for trade execution (e.g., FlexiblePrice, PrivateSale)
    address currency; // currency (e.g., WETH)
    uint256 nonce; // order nonce (must be unique unless new maker order is meant to override existing one e.g., lower ask price)
    bytes startAndEndTimes; // startTime and endTime in block.timestamp
    uint256 minPercentageToAsk; // slippage protection (9000 --> 90% of the final price must return to ask)
    bytes params; // additional parameters
    bytes sig; // uint8 v: parameter (27 or 28), bytes32 r, bytes32 s
  }

  struct TakerOrder {
    bool isOrderAsk; // true --> ask / false --> bid
    address taker; // msg.sender
    uint256 price; // final price for the purchase
    uint256 tokenId;
    uint256 minPercentageToAsk; // // slippage protection (9000 --> 90% of the final price must return to ask)
    bytes params; // other params (e.g., tokenId)
  }

  function hash(MakerOrder memory makerOrder) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          MAKER_ORDER_HASH,
          makerOrder.isOrderAsk,
          makerOrder.signer,
          makerOrder.collection,
          keccak256(makerOrder.prices),
          makerOrder.tokenId,
          makerOrder.amount,
          makerOrder.strategy,
          makerOrder.currency,
          makerOrder.nonce,
          keccak256(makerOrder.startAndEndTimes),
          makerOrder.minPercentageToAsk,
          keccak256(makerOrder.params)
        )
      );
  }
}
