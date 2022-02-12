// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExecutionManager {
  function isStrategyWhitelisted(address strategy) external view returns (bool);
}
