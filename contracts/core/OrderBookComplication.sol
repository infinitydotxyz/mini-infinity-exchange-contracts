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

  function canExecOBOrder(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) external view returns (bool) {
    // check timestamps
    (uint256 sellStartTime, uint256 sellEndTime) = (sell.constraints[3], sell.constraints[4]);
    (uint256 buyStartTime, uint256 buyEndTime) = (buy.constraints[3], buy.constraints[4]);
    bool isSellTimeValid = sellStartTime <= block.timestamp && sellEndTime >= block.timestamp;
    bool isBuyTimeValid = buyStartTime <= block.timestamp && buyEndTime >= block.timestamp;
    bool isTimeValid = isSellTimeValid && isBuyTimeValid;

    (uint256 currentSellPrice, uint256 currentBuyPrice, uint256 currentConstrPrice) = _getCurrentPrices(sell, buy, constructed);
    bool isAmountValid = Utils.arePricesWithinErrorBound(currentConstrPrice, currentBuyPrice, ERROR_BOUND) &&
      Utils.arePricesWithinErrorBound(currentBuyPrice, currentSellPrice, ERROR_BOUND);
    bool numItemsValid = constructed.constraints[0] >= buy.constraints[0] && buy.constraints[0] <= sell.constraints[0];
    return isTimeValid && isAmountValid && numItemsValid;
  }

  function canExecTakeOBOrder(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder) external view returns (bool) {
    // check timestamps
    (uint256 startTime, uint256 endTime) = (makerOrder.constraints[3], makerOrder.constraints[4]);
    bool isTimeValid = startTime <= block.timestamp && endTime >= block.timestamp;

    (uint256 currentMakerPrice, uint256 currentTakerPrice) = (Utils.getCurrentPrice(makerOrder), Utils.getCurrentPrice(takerOrder));
    bool isAmountValid = Utils.arePricesWithinErrorBound(currentMakerPrice, currentTakerPrice, ERROR_BOUND);
    bool numItemsValid = makerOrder.constraints[0] == takerOrder.constraints[0];
    return isTimeValid && isAmountValid && numItemsValid;
  }

  function canExecOrder(OrderTypes.Maker calldata, OrderTypes.Taker calldata)
    external
    pure
    returns (
      bool,
      uint256,
      uint256
    )
  {
    return (false, 0, 0);
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

  function _getCurrentPrices(
    OrderTypes.Order calldata sell,
    OrderTypes.Order calldata buy,
    OrderTypes.Order calldata constructed
  ) internal view returns (uint256, uint256, uint256) {
    uint256 sellPrice = Utils.getCurrentPrice(sell);
    uint256 buyPrice = Utils.getCurrentPrice(buy);
    uint256 constructedPrice = Utils.getCurrentPrice(constructed);
    return (sellPrice, buyPrice, constructedPrice);
  }
}
