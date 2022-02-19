// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libraries/OrderTypes.sol';

interface IExecutionStrategy {
  function canExecuteTakerSell(OrderTypes.Taker calldata takerSell, OrderTypes.Maker calldata makerBuy)
    external
    view
    returns (
      bool,
      uint256,
      uint256
    );

  function canExecuteTakerBuy(OrderTypes.Taker calldata takerBuy, OrderTypes.Maker calldata makerSell)
    external
    view
    returns (
      bool,
      uint256,
      uint256
    );

  function viewProtocolFee() external view returns (uint256);
}
