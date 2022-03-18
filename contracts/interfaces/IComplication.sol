// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

interface IComplication {
  function canExecOBOrder(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) external view returns (bool);

  function canExecTakeOBOrder(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder)
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
