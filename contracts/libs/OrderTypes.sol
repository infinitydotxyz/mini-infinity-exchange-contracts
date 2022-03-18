// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OrderTypes
 */
library OrderTypes {
  // keccak256("Order(bool isSellOrder,address signer,uint256[] constraints,Items[] nfts,address[] execParams,bytes extraParams)")
  bytes32 internal constant ORDER_HASH = 0x496b168c8870e3f5cf5105d5234e56421655698f1d0a04554c8863382442881a;

  struct Item {
    address collection;
    uint256[] tokenIds;
  }

  struct Order {
    // is order sell or buy
    bool isSellOrder;
    address signer;
    // total length: 7
    // in order:
    // numItems - min/max number of items in the order
    // start and end prices in wei
    // start and end times in block.timestamp
    // minBpsToSeller
    // nonce
    uint256[] constraints;
    // collections and tokenIds constraints
    Item[] nfts;
    // address of complication for trade execution (e.g. OrderBook), address of the currency (e.g., WETH)
    address[] execParams;
    // additional parameters like rarities, private sale buyer etc
    bytes extraParams;
    // uint8 v: parameter (27 or 28), bytes32 r, bytes32 s
    bytes sig;
  }

  function hash(Order memory order) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          ORDER_HASH,
          order.isSellOrder,
          order.signer,
          order.constraints,
          order.nfts,
          order.execParams,
          keccak256(order.extraParams)
        )
      );
  }
}
