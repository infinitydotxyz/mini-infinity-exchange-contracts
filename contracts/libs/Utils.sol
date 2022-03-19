// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

library Utils {
  using OrderTypes for OrderTypes.Item;
  using OrderTypes for OrderTypes.Order;

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

  function checkItemsIntersect(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder)
    public
    pure
    returns (bool)
  {
    // case where maker/taker didn't specify any items
    if (makerOrder.nfts.length == 0 || takerOrder.nfts.length == 0) {
      return true;
    }

    uint256 numCollsMatched = 0;
    // check if taker has all items in maker
    for (uint256 i = 0; i < takerOrder.nfts.length; ) {
      for (uint256 j = 0; j < makerOrder.nfts.length; ) {
        if (makerOrder.nfts[j].collection == takerOrder.nfts[i].collection) {
          // increment numCollsMatched
          unchecked {
            ++numCollsMatched;
          }
          // check if tokenIds intersect
          bool tokenIdsIntersect = _checkTokenIdsIntersect(makerOrder.nfts[j], takerOrder.nfts[i]);
          require(tokenIdsIntersect, 'taker cant have more tokenIds per coll than maker');
          // short circuit
          break;
        }
        unchecked {
          ++j;
        }
      }
      unchecked {
        ++i;
      }
    }
    return numCollsMatched == takerOrder.nfts.length;
  }

  function _checkTokenIdsIntersect(OrderTypes.Item calldata makerItem, OrderTypes.Item calldata takerItem)
    internal
    pure
    returns (bool)
  {
    // case where maker/taker didn't specify any tokenIds for this collection
    if (makerItem.tokenIds.length == 0 || takerItem.tokenIds.length == 0) {
      return true;
    }
    uint256 numTokenIdsPerCollMatched = 0;
    for (uint256 k = 0; k < takerItem.tokenIds.length; ) {
      for (uint256 l = 0; l < makerItem.tokenIds.length; ) {
        if (makerItem.tokenIds[l] == takerItem.tokenIds[k]) {
          // increment numTokenIdsPerCollMatched
          unchecked {
            ++numTokenIdsPerCollMatched;
          }
          break;
        }
        unchecked {
          ++l;
        }
      }
      unchecked {
        ++k;
      }
    }
    return numTokenIdsPerCollMatched == takerItem.tokenIds.length;
  }
}
