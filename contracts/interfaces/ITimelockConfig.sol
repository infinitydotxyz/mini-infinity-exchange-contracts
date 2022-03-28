// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITimelockConfig {
  struct Config {
    bytes32 id;
    uint256 value;
  }

  struct PendingRequest {
    bytes32 id;
    uint256 value;
    uint256 timestamp;
  }

  event ChangeRequested(bytes32 configID, uint256 value);
  event ChangeConfirmed(bytes32 configID, uint256 value);
  event ChangeCanceled(bytes32 configID, uint256 value);

  // =============================================== USER FUNCTIONS =========================================================

  function confirmChange(bytes32 configID) external;

  // =============================================== VIEW FUNCTIONS =========================================================

  function calculateConfigID(string memory name) external pure returns (bytes32 configID);

  function getConfig(bytes32 configID) external view returns (Config memory config);

  function isConfig(bytes32 configID) external view returns (bool status);

  function getConfigCount() external view returns (uint256 count);

  function getConfigByIndex(uint256 index) external view returns (Config memory config);

  function getPending(bytes32 configID) external view returns (PendingRequest memory pendingRequest);

  function isPending(bytes32 configID) external view returns (bool status);

  function getPendingCount() external view returns (uint256 count);

  function getPendingByIndex(uint256 index) external view returns (PendingRequest memory pendingRequest);

  // =============================================== ADMIN FUNCTIONS =========================================================

  function requestChange(bytes32 configID, uint256 value) external;

  function cancelChange(bytes32 configID) external;
}
