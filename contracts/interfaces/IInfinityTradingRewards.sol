// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {Duration} from '../interfaces/IStaker.sol';

interface IInfinityTradingRewards {
  function updateRewards(
    address[] calldata sellers,
    address[] calldata buyers,
    address[] calldata currencies,
    uint256[] calldata amounts
  ) external;

  function claimRewards(
    address currency,
    uint256 amount
  ) external;

  function stakeInfinityRewards(uint256 amount, Duration duration) external;
}
