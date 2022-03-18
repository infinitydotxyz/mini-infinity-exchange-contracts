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
    (uint256 makerCurrentPrice, uint256 takerCurrentPrice) = (
      Utils.getCurrentPrice(makerOrder),
      Utils.getCurrentPrice(takerOrder)
    );
    (uint256 startTime, uint256 endTime) = (makerOrder.constraints[3], makerOrder.constraints[4]);
    bool numItemsValid = makerOrder.constraints[0] == takerOrder.constraints[0];
    return ((targetBuyer == takerOrder.signer &&
      Utils.arePricesWithinErrorBound(makerCurrentPrice, takerCurrentPrice, ERROR_BOUND) &&
      startTime <= block.timestamp &&
      endTime >= block.timestamp) && numItemsValid);
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
