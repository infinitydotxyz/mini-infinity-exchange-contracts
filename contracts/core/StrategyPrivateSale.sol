// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes, Utils} from '../libraries/Utils.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title StrategyPrivateSale
 * @notice Strategy to set up an order that can only be executed by
 * a specific address.
 */
contract StrategyPrivateSale is IExecutionStrategy, Ownable {
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
   * @notice Check whether a taker ask order can be executed against a maker bid
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteTakerAsk(OrderTypes.TakerOrder calldata, OrderTypes.MakerOrder calldata)
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
   * @notice Check whether a taker bid order can be executed against a maker ask
   * @param takerBid taker bid order
   * @param makerAsk maker ask order
   * @return (whether strategy can be executed, tokenId to execute, amount of tokens to execute)
   */
  function canExecuteTakerBid(OrderTypes.TakerOrder calldata takerBid, OrderTypes.MakerOrder calldata makerAsk)
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
    address targetBuyer = abi.decode(makerAsk.params, (address));
    uint256 currentPrice = Utils.calculateCurrentPrice(makerAsk);
    (uint256 startTime, uint256 endTime) = abi.decode(makerAsk.startAndEndTimes, (uint256, uint256));
    return (
      (targetBuyer == takerBid.taker &&
        Utils.arePricesWithinErrorBound(currentPrice, takerBid.price, ERROR_BOUND) &&
        makerAsk.tokenId == takerBid.tokenId &&
        startTime <= block.timestamp &&
        endTime >= block.timestamp),
      makerAsk.tokenId,
      makerAsk.amount
    );
  }

  /**
   * @notice Return protocol fee for this strategy
   * @return protocol fee
   */
  function viewProtocolFee() external view override returns (uint256) {
    return PROTOCOL_FEE;
  }

  function setErrorBound(uint256 _errorBound) external onlyOwner {
    ERROR_BOUND = _errorBound;
    emit NewErrorbound(_errorBound);
  }
}
