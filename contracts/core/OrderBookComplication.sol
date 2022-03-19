// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libs/Utils.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title OrderBookComplication
 * @notice Complication to execute orderbook orders
 */
contract OrderBookComplication is IComplication, Ownable {
  uint256 public immutable PROTOCOL_FEE;
  uint256 public ERROR_BOUND; // error bound for prices in wei

  event NewErrorbound(uint256 errorBound);

  /**
   * @notice Constructor
   * @param _protocolFee protocol fee (200 --> 2%, 400 --> 4%)
   * @param _errorBound price error bound in wei
   */
  constructor(uint256 _protocolFee, uint256 _errorBound) {
    PROTOCOL_FEE = _protocolFee;
    ERROR_BOUND = _errorBound;
  }

  function canExecOrder(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) external view returns (bool) {
    bool isTimeValid = _isTimeValid(sell, buy);
    bool isAmountValid = _isAmountValid(sell, buy, constructed);
    bool numItemsValid = constructed.constraints[0] >= buy.constraints[0] && buy.constraints[0] <= sell.constraints[0];
    bool itemsIntersect = Utils.checkItemsIntersect(sell, constructed) && Utils.checkItemsIntersect(buy, constructed);

    return isTimeValid && isAmountValid && numItemsValid && itemsIntersect;
  }

  function _isTimeValid(OrderTypes.Order calldata sell, OrderTypes.Order calldata buy) internal view returns (bool) {
    (uint256 sellStartTime, uint256 sellEndTime) = (sell.constraints[3], sell.constraints[4]);
    (uint256 buyStartTime, uint256 buyEndTime) = (buy.constraints[3], buy.constraints[4]);
    bool isSellTimeValid = sellStartTime <= block.timestamp && sellEndTime >= block.timestamp;
    bool isBuyTimeValid = buyStartTime <= block.timestamp && buyEndTime >= block.timestamp;

    return isSellTimeValid && isBuyTimeValid;
  }

  function _isAmountValid(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) internal view returns (bool) {
    (uint256 currentSellPrice, uint256 currentBuyPrice, uint256 currentConstructedPrice) = (
      Utils.getCurrentPrice(sell),
      Utils.getCurrentPrice(buy),
      Utils.getCurrentPrice(constructed)
    );
    return
      Utils.arePricesWithinErrorBound(currentConstructedPrice, currentBuyPrice, ERROR_BOUND) &&
      Utils.arePricesWithinErrorBound(currentBuyPrice, currentSellPrice, ERROR_BOUND);
  }

  function canExecTakeOrder(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder)
    external
    view
    returns (bool)
  {
    // check timestamps
    (uint256 startTime, uint256 endTime) = (makerOrder.constraints[3], makerOrder.constraints[4]);
    bool isTimeValid = startTime <= block.timestamp && endTime >= block.timestamp;

    (uint256 currentMakerPrice, uint256 currentTakerPrice) = (
      Utils.getCurrentPrice(makerOrder),
      Utils.getCurrentPrice(takerOrder)
    );
    bool isAmountValid = Utils.arePricesWithinErrorBound(currentMakerPrice, currentTakerPrice, ERROR_BOUND);
    bool numItemsValid = makerOrder.constraints[0] == takerOrder.constraints[0];
    bool itemsIntersect = Utils.checkItemsIntersect(makerOrder, takerOrder);

    return isTimeValid && isAmountValid && numItemsValid && itemsIntersect;
  }

  /**
   * @notice Return protocol fee for this complication
   * @return protocol fee
   */
  function getProtocolFee() external view override returns (uint256) {
    return PROTOCOL_FEE;
  }

  function setErrorBound(uint256 _errorBound) external onlyOwner {
    ERROR_BOUND = _errorBound;
    emit NewErrorbound(_errorBound);
  }
}
