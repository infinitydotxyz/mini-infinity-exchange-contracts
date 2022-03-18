// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

interface IInfinityExchange {
  function takeOBOrders(OrderTypes.Order[] calldata makerOrders, OrderTypes.Order[] calldata takerOrders) external;

  function matchOBOrders(
    OrderTypes.Order[] calldata sells,
    OrderTypes.Order[] calldata buys,
    OrderTypes.Order[] calldata constructs
  ) external;

  function execOrders(OrderTypes.Maker[] calldata makerOrders, OrderTypes.Taker[] calldata takerOrders) external;
}
