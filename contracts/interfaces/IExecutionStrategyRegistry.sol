// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExecutionStrategyRegistry {
  function isStrategyWhitelisted(address strategy) external view returns (bool);
}
