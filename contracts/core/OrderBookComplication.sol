// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';
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
    OrderTypes.OrderBook calldata sell,
    OrderTypes.OrderBook calldata buy,
    OrderTypes.OrderBook calldata constructed
  ) external view returns (bool) {
    // check timestamps
    (uint256 sellStartTime, uint256 sellEndTime) = abi.decode(sell.startAndEndTimes, (uint256, uint256));
    (uint256 buyStartTime, uint256 buyEndTime) = abi.decode(buy.startAndEndTimes, (uint256, uint256));
    bool isSellTimeValid = sellStartTime <= block.timestamp && sellEndTime >= block.timestamp;
    bool isBuyTimeValid = buyStartTime <= block.timestamp && buyEndTime >= block.timestamp;
    bool isTimeValid = isSellTimeValid && isBuyTimeValid;

    bool isAmountValid = constructed.amount <= buy.amount && buy.amount >= sell.amount;
    bool numItemsValid = constructed.numItems >= buy.numItems && buy.numItems <= sell.numItems;
    return isTimeValid && isAmountValid && numItemsValid;
  }

  function canExecTakeOBOrder(OrderTypes.OrderBook calldata, OrderTypes.OrderBook calldata)
    external
    pure
    returns (bool)
  {
    return false;
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
}
