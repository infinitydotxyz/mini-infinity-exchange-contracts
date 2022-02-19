// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IExecutionStrategyRegistry} from '../interfaces/IExecutionStrategyRegistry.sol';

/**
 * @title ExecutionStrategyRegistry
 * @notice allows adding/removing execution strategies for trading on the Infinity exchange
 */
contract ExecutionStrategyRegistry is IExecutionStrategyRegistry, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _whitelistedStrategies;

  event StrategyRemoved(address indexed strategy);
  event StrategyWhitelisted(address indexed strategy);

  /**
   * @notice Adds an execution strategy
   * @param strategy address of the strategy to add
   */
  function addStrategy(address strategy) external onlyOwner {
    require(!_whitelistedStrategies.contains(strategy), 'Strategy: Already whitelisted');
    _whitelistedStrategies.add(strategy);

    emit StrategyWhitelisted(strategy);
  }

  /**
   * @notice Remove an execution strategy
   * @param strategy address of the strategy to remove
   */
  function removeStrategy(address strategy) external onlyOwner {
    require(_whitelistedStrategies.contains(strategy), 'Strategy: Not whitelisted');
    _whitelistedStrategies.remove(strategy);

    emit StrategyRemoved(strategy);
  }

  /**
   * @notice Returns if an execution strategy was whitelisted
   * @param strategy address of the strategy
   */
  function isStrategyWhitelisted(address strategy) external view override returns (bool) {
    return _whitelistedStrategies.contains(strategy);
  }

  /**
   * @notice View number of whitelisted strategies
   */
  function numWhitelistedStrategies() external view returns (uint256) {
    return _whitelistedStrategies.length();
  }

  /**
   * @notice See whitelisted strategies
   * @param cursor cursor (should start at 0 for first request)
   * @param size size of the response (e.g., 50)
   */
  function getWhitelistedStrategies(uint256 cursor, uint256 size) external view returns (address[] memory, uint256) {
    uint256 length = size;

    if (length > _whitelistedStrategies.length() - cursor) {
      length = _whitelistedStrategies.length() - cursor;
    }

    address[] memory whitelistedStrategies = new address[](length);

    for (uint256 i = 0; i < length; i++) {
      whitelistedStrategies[i] = _whitelistedStrategies.at(cursor + i);
    }

    return (whitelistedStrategies, cursor + length);
  }
}
