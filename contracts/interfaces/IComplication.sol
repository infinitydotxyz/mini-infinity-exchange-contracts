// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

interface IComplication {
  function canExecOBOrder(
    OrderTypes.OrderBook calldata sell,
    OrderTypes.OrderBook calldata buy,
    OrderTypes.OrderBook calldata constructed
  ) external view returns (bool);

  function canExecTakeOBOrder(OrderTypes.OrderBook calldata makerOrder, OrderTypes.OrderBook calldata takerOrder)
    external
    view
    returns (bool);

  function canExecOrder(OrderTypes.Maker calldata makerOrder, OrderTypes.Taker calldata takerOrder)
    external
    view
    returns (
      bool,
      uint256,
      uint256
    );

  function getProtocolFee() external view returns (uint256);
}
