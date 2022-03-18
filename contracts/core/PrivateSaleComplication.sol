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

  /**
   * @notice Check whether order can be executed
   * @param makerOrder maker order
   * @param takerOrder taker order
   * @return (whether complication can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecOrder(OrderTypes.Maker calldata makerOrder, OrderTypes.Taker calldata takerOrder)
    external
    view
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    // Retrieve target buyer
    address targetBuyer = abi.decode(makerOrder.params, (address));
    uint256 currentPrice = Utils.calculateCurrentPrice(makerOrder);
    (uint256 startTime, uint256 endTime) = abi.decode(makerOrder.startAndEndTimes, (uint256, uint256));
    (uint256 tokenId, uint256 amount) = abi.decode(makerOrder.tokenInfo, (uint256, uint256));
    (bool isSellOrder, , , ) = abi.decode(makerOrder.execInfo, (bool, address, address, uint256));
    return (
      (isSellOrder &&
        targetBuyer == takerOrder.taker &&
        Utils.arePricesWithinErrorBound(currentPrice, takerOrder.price, ERROR_BOUND) &&
        tokenId == takerOrder.tokenId &&
        startTime <= block.timestamp &&
        endTime >= block.timestamp),
      tokenId,
      amount
    );
  }

  function canExecOBOrder(
    OrderTypes.Order calldata,
    OrderTypes.Order calldata,
    OrderTypes.Order calldata
  ) external pure returns (bool) {
    return false;
  }

  function canExecTakeOBOrder(OrderTypes.Order calldata, OrderTypes.Order calldata) external pure returns (bool) {
    return false;
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
