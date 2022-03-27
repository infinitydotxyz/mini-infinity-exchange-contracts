// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderTypes} from '../libs/OrderTypes.sol';

enum Duration {
  NONE,
  THREE_MONTHS,
  SIX_MONTHS,
  TWELVE_MONTHS
}

interface IStaker {
  function stake(uint256 amount, Duration duration) external;

  function lock(uint256 amount, Duration duration) external;

  function changeDuration(uint256 amount, Duration oldDuration, Duration newDuration) external;

  function unstake(uint256 amount) external;

  function rageQuit() external;
}
