// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

library Utils {
  function calculateCurrentPrice(OrderTypes.Maker calldata makerOrder) public view returns (uint256) {
    (uint256 startTime, uint256 endTime) = abi.decode(makerOrder.startAndEndTimes, (uint256, uint256));
    (uint256 startPrice, uint256 endPrice, ) = abi.decode(makerOrder.prices, (uint256, uint256, uint256));
    uint256 duration = endTime - startTime;
    uint256 priceDiff = startPrice - endPrice;
    if (priceDiff == 0 || duration == 0) {
      return startPrice;
    }
    uint256 elapsedTime = block.timestamp - startTime;
    uint256 portion = elapsedTime > duration ? 1 : elapsedTime / duration;
    priceDiff = priceDiff * portion;
    return startPrice - priceDiff;
  }

  function getCurrentPrice(OrderTypes.Order calldata order) public view returns (uint256) {
    (uint256 startPrice, uint256 endPrice) = (order.constraints[1], order.constraints[2]);
    (uint256 startTime, uint256 endTime) = (order.constraints[3], order.constraints[4]);
    uint256 duration = endTime - startTime;
    uint256 priceDiff = startPrice - endPrice;
    if (priceDiff == 0 || duration == 0) {
      return startPrice;
    }
    uint256 elapsedTime = block.timestamp - startTime;
    uint256 portion = elapsedTime > duration ? 1 : elapsedTime / duration;
    priceDiff = priceDiff * portion;
    return startPrice - priceDiff;
  }

  function arePricesWithinErrorBound(
    uint256 price1,
    uint256 price2,
    uint256 errorBound
  ) public pure returns (bool) {
    if (price1 == price2) {
      return true;
    } else if (price1 > price2 && price1 - price2 <= errorBound) {
      return true;
    } else if (price2 > price1 && price2 - price1 <= errorBound) {
      return true;
    } else {
      return false;
    }
  }
}
