// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libraries/OrderTypes.sol';

interface IInfinityExchange {
  function takeOBOrders(
    OrderTypes.OrderBook[] calldata makerOrders,
    OrderTypes.OrderBook[] calldata takerOrders
  ) external;

  function matchOBOrders(
    OrderTypes.OrderBook[] calldata sells,
    OrderTypes.OrderBook[] calldata buys,
    OrderTypes.OrderBook[] calldata constructs
  ) external;

  function execOrders(OrderTypes.Maker[] calldata makerOrders, OrderTypes.Taker[] calldata takerOrders) external;
}
