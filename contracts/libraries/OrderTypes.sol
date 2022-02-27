// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OrderTypes
 */
library OrderTypes {
  // keccak256("Maker(address signer,address collection,bytes prices,bytes startAndEndTimes,bytes tokenInfo,bytes execInfo,bytes params)")
  bytes32 internal constant MAKER_ORDER_HASH = 0x23eb33010eff990b48001f1b215dca65dd1b266e3cf1712ed9814d12c0fc1803;

  struct Maker {
    address signer; // signer of the order
    address collection; // collection address
    bytes prices; // uint256 startPrice, uint256 endPrice, uint256 minBpsToSeller (9000 --> 90% of the final price must return to sell)
    bytes startAndEndTimes; // uint256 startTime and uint256 endTime in block.timestamp
    bytes tokenInfo; // uint256 id of the token and uint256 amount of tokens to sell/purchase (must be 1 for ERC721, 1+ for ERC1155)
    bytes execInfo; // bool isListing, address of complication for trade execution (e.g., FlexiblePrice, PrivateSale), address of the currency (e.g., WETH) and uint256 nonce of the order (must be unique unless new maker order is meant to override existing one e.g., lower sell price)
    bytes params; // additional parameters
    bytes sig; // uint8 v: parameter (27 or 28), bytes32 r, bytes32 s
  }

  struct Taker {
    bool isSellOrder;
    address taker; // msg.sender
    uint256 price; // final price
    uint256 tokenId;
    uint256 minBpsToSeller; // (9000 --> 90% of the final price must return to sell)
    bytes params; // additional parameters
  }

  function hash(Maker memory makerOrder) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          MAKER_ORDER_HASH,
          makerOrder.signer,
          makerOrder.collection,
          keccak256(makerOrder.prices),
          keccak256(makerOrder.startAndEndTimes),
          keccak256(makerOrder.tokenInfo),
          keccak256(makerOrder.execInfo),
          keccak256(makerOrder.params)
        )
      );
  }
}
