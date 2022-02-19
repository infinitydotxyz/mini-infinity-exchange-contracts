// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libraries/OrderTypes.sol';

interface IInfinityExchange {
  function matchMakerSellsWithTakerBuys(OrderTypes.Maker[] calldata makerSells, OrderTypes.Taker[] calldata takerBuys)
    external;

  function matchMakerBuysWithTakerSells(OrderTypes.Maker[] calldata makerBuys, OrderTypes.Taker[] calldata takerSells)
    external;
}
