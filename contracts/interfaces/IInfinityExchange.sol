// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

interface IInfinityExchange {
  function takeOrders(OrderTypes.Order[] calldata makerOrders, OrderTypes.Order[] calldata takerOrders) external;

  function matchOrders(
    OrderTypes.Order[] calldata sells,
    OrderTypes.Order[] calldata buys,
    OrderTypes.Order[] calldata constructs
  ) external;
}
