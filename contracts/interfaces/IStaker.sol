// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

enum Duration {
  NONE,
  THREE_MONTHS,
  SIX_MONTHS,
  TWELVE_MONTHS
}

enum StakeLevel {
  BRONZE,
  SILVER,
  GOLD,
  PLATINUM
}

interface IStaker {
  function stake(address user, uint256 amount, Duration duration) external;

  function changeDuration(address user, uint256 amount, Duration oldDuration, Duration newDuration) external;

  function unstake(address user, uint256 amount) external;

  function rageQuit() external;

  function getUserTotalStaked(address user) external view returns (uint256);

  function getUserTotalVested(address user) external view returns (uint256);

  function getUserStakePower(address user) external view returns (uint256);

  function getUserStakeLevel(address user) external view returns (StakeLevel);
}
