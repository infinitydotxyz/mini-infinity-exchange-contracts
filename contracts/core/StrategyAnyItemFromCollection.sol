// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libraries/Utils.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title StrategyAnyItemFromCollection
 * @notice Strategy to send an order at a flexible price that can be matched by any tokenId for the collection.
 */
contract StrategyAnyItemFromCollection is IExecutionStrategy, Ownable {
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
   * @notice Check whether a taker accept order can be executed against a maker offer
   * @param accept taker accept order
   * @param offer maker offer
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteOffer(OrderTypes.Taker calldata accept, OrderTypes.Maker calldata offer)
    external
    view
    override
    returns (
      bool,
      uint256,
      uint256
    )
  {
    uint256 currentPrice = Utils.calculateCurrentPrice(offer);
    (uint256 startTime, uint256 endTime) = abi.decode(offer.startAndEndTimes, (uint256, uint256));
    (, uint256 amount) = abi.decode(offer.tokenInfo, (uint256, uint256));
    return (
      (Utils.arePricesWithinErrorBound(currentPrice, accept.price, ERROR_BOUND) &&
        startTime <= block.timestamp &&
        endTime >= block.timestamp),
      accept.tokenId,
      amount
    );
  }

  /**
   * @notice Check whether a taker buy order can be executed against a maker listing
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteListing(OrderTypes.Taker calldata, OrderTypes.Maker calldata)
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
  function getProtocolFee() external view override returns (uint256) {
    return PROTOCOL_FEE;
  }

  function setErrorBound(uint256 _errorBound) external onlyOwner {
    ERROR_BOUND = _errorBound;
    emit NewErrorbound(_errorBound);
  }
}
