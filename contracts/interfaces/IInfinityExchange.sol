// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libraries/OrderTypes.sol';

interface IInfinityExchange {
  function matchMakerAsksWithTakerBids(OrderTypes.MakerOrder[] calldata makerAsks, OrderTypes.TakerOrder[] calldata takerBids)
    external;

  function matchMakerBidsWithTakerAsks(OrderTypes.MakerOrder[] calldata makerBids, OrderTypes.TakerOrder[] calldata takerAsks)
    external;
}
