// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libraries/OrderTypes.sol';

interface IInfinityExchange {
  function matchListingsWithBuys(OrderTypes.Maker[] calldata listings, OrderTypes.Taker[] calldata buys)
    external;

  function matchOffersWithAccepts(OrderTypes.Maker[] calldata offers, OrderTypes.Taker[] calldata accepts)
    external;
}
