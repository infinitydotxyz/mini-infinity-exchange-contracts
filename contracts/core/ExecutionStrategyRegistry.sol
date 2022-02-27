// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IComplicationRegistry} from '../interfaces/IComplicationRegistry.sol';

/**
 * @title ComplicationRegistry
 * @notice allows adding/removing execution strategies for trading on the Infinity exchange
 */
contract ComplicationRegistry is IComplicationRegistry, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _whitelistedStrategies;

  event ComplicationRemoved(address indexed complication);
  event ComplicationWhitelisted(address indexed complication);

  /**
   * @notice Adds an execution complication
   * @param complication address of the complication to add
   */
  function addComplication(address complication) external onlyOwner {
    require(!_whitelistedStrategies.contains(complication), 'Complication: Already whitelisted');
    _whitelistedStrategies.add(complication);

    emit ComplicationWhitelisted(complication);
  }

  /**
   * @notice Remove an execution complication
   * @param complication address of the complication to remove
   */
  function removeComplication(address complication) external onlyOwner {
    require(_whitelistedStrategies.contains(complication), 'Complication: Not whitelisted');
    _whitelistedStrategies.remove(complication);

    emit ComplicationRemoved(complication);
  }

  /**
   * @notice Returns if an execution complication was whitelisted
   * @param complication address of the complication
   */
  function isComplicationWhitelisted(address complication) external view override returns (bool) {
    return _whitelistedStrategies.contains(complication);
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
