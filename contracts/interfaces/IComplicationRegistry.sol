// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IComplicationRegistry {
  function isComplicationWhitelisted(address complication) external view returns (bool);
}
