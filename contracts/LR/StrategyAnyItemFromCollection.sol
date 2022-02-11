// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libraries/Utils.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title StrategyAnyItemFromCollection
 * @notice Strategy to send an order at a flexible price that can be
 * matched by any tokenId for the collection.
 */
contract StrategyAnyItemFromCollection is IExecutionStrategy, Ownable {
  uint256 public PROTOCOL_FEE;
  uint256 public ERROR_BOUND; // error bound for prices in wei

  event NewProtocolFee(uint256 protocolFee);
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
   * @notice Check whether a taker ask order can be executed against a maker bid
   * @param takerAsk taker ask order
   * @param makerBid maker bid order
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteTakerAsk(OrderTypes.TakerOrder calldata takerAsk, OrderTypes.MakerOrder calldata makerBid)
    external
    view
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    uint256 currentPrice = Utils.calculateCurrentPrice(makerBid);
    (uint256 startTime, uint256 endTime) = abi.decode(makerBid.startAndEndTimes, (uint256, uint256));
    return (
      (Utils.arePricesWithinErrorBound(currentPrice, takerAsk.price, ERROR_BOUND) &&
        startTime <= block.timestamp &&
        endTime >= block.timestamp),
      takerAsk.tokenId,
      makerBid.amount
    );
  }

  /**
   * @notice Check whether a taker bid order can be executed against a maker ask
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteTakerBid(OrderTypes.TakerOrder calldata, OrderTypes.MakerOrder calldata)
    external
    pure
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    return (false, 0, 0);
  }

  /**
   * @notice Return protocol fee for this strategy
   * @return protocol fee
   */
  function viewProtocolFee() external view override returns (uint256) {
    return PROTOCOL_FEE;
  }

  function setProtocolFee(uint256 _protocolFee) external onlyOwner {
    PROTOCOL_FEE = _protocolFee;
    emit NewProtocolFee(_protocolFee);
  }

  function setErrorBound(uint256 _errorBound) external onlyOwner {
    ERROR_BOUND = _errorBound;
    emit NewErrorbound(_errorBound);
  }
}
