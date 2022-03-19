// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libs/Utils.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title PrivateSaleComplication
 * @notice Complication that specifies an order that can only be executed by a specific address
 */
contract PrivateSaleComplication is IComplication, Ownable {
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
    OrderTypes.Order calldata,
    OrderTypes.Order calldata,
    OrderTypes.Order calldata
  ) external pure returns (bool) {
    return false;
  }

  function canExecTakeOrder(OrderTypes.Order calldata makerOrder, OrderTypes.Order calldata takerOrder)
    external
    view
    returns (bool)
  {
    address targetBuyer = abi.decode(makerOrder.extraParams, (address));
    bool isBuyerValid = targetBuyer == takerOrder.signer;

    (uint256 startTime, uint256 endTime) = (makerOrder.constraints[3], makerOrder.constraints[4]);
    bool isTimeValid = startTime <= block.timestamp && endTime >= block.timestamp;

    (uint256 currentMakerPrice, uint256 currentTakerPrice) = (
      Utils.getCurrentPrice(makerOrder),
      Utils.getCurrentPrice(takerOrder)
    );
    bool isAmountValid = Utils.arePricesWithinErrorBound(currentMakerPrice, currentTakerPrice, ERROR_BOUND);
    bool numItemsValid = makerOrder.constraints[0] == takerOrder.constraints[0];
    bool itemsIntersect = Utils.checkItemsIntersect(makerOrder, takerOrder);

    return isBuyerValid && isAmountValid && isTimeValid && numItemsValid && itemsIntersect;
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
