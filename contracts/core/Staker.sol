// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Pausable} from '@openzeppelin/contracts/security/Pausable.sol';
import {IStaker, Duration, StakeLevel} from '../interfaces/IStaker.sol';
import 'hardhat/console.sol'; // todo: remove this

contract Staker is IStaker, Ownable, Pausable {
  using SafeERC20 for IERC20;
  mapping(address => mapping(Duration => uint256)) public userstakedAmounts;
  address tokenAddress;
  uint32 public BRONZE_STAKE_LEVEL = 1000;
  uint32 public SILVER_STAKE_LEVEL = 5000;
  uint32 public GOLD_STAKE_LEVEL = 10000;

  event Staked(address indexed user, uint256 amount, Duration duration);
  event Locked(address indexed user, uint256 amount, Duration duration);
  event DurationChanged(address indexed user, uint256 amount, Duration oldDuration, Duration newDuration);
  event UnStaked(address indexed user, uint256 amount);
  event RageQuit(address indexed user, uint256 amount);

  constructor(address _tokenAddress) {
    tokenAddress = _tokenAddress;
  }

  // =================================================== USER FUNCTIONS =======================================================
  function stake(uint256 amount, Duration duration) external whenNotPaused {
    require(amount != 0, 'stake amount cant be 0');
    require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, 'insufficient balance to stake');

    // update storage
    userstakedAmounts[msg.sender][duration] += amount;
    // perform transfer
    IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
    // emit event
    emit Staked(msg.sender, amount, duration);
  }

  function lock(uint256 amount, Duration duration) external whenNotPaused {
    require(amount != 0, 'lock amount cant be 0');
    require(userstakedAmounts[msg.sender][Duration.NONE] >= amount, 'insufficient balance to lock');
    require(duration != Duration.NONE, 'cant lock for duration NONE');

    // update storage
    userstakedAmounts[msg.sender][Duration.NONE] -= amount;
    userstakedAmounts[msg.sender][duration] += amount;
    // emit event
    emit Locked(msg.sender, amount, duration);
  }

  function changeDuration(
    uint256 amount,
    Duration oldDuration,
    Duration newDuration
  ) external whenNotPaused {
    require(amount != 0, 'amount cant be 0');
    require(userstakedAmounts[msg.sender][oldDuration] >= amount, 'insufficient staked amount to change duration');

    // update storage
    userstakedAmounts[msg.sender][oldDuration] -= amount;
    userstakedAmounts[msg.sender][newDuration] += amount;
    // emit event
    emit DurationChanged(msg.sender, amount, oldDuration, newDuration);
  }

  function unstake(uint256 amount) external whenNotPaused {
    require(amount != 0, 'stake amount cant be 0');
    require(userstakedAmounts[msg.sender][Duration.NONE] >= amount, 'insufficient balance to unstake');

    // update storage
    userstakedAmounts[msg.sender][Duration.NONE] -= amount;
    // perform transfer
    IERC20(tokenAddress).safeTransferFrom(address(this), msg.sender, amount);
    // emit event
    emit UnStaked(msg.sender, amount);
  }

  function rageQuit() external {
    uint256 totalStaked = _getUserTotalStaked(msg.sender);
    require(totalStaked >= 0, 'nothing staked to rage quit');

    // update storage
    _clearUserStakedAmounts(msg.sender);
    // perform transfer
    IERC20(tokenAddress).safeTransferFrom(address(this), msg.sender, totalStaked);
    // emit event
    emit RageQuit(msg.sender, totalStaked);
  }

  // ====================================================== VIEW FUNCTIONS ======================================================

  function getUserTotalStaked(address user) external view returns (uint256) {
    return _getUserTotalStaked(user);
  }

  function getUserStakeLevel(address user) external view returns (StakeLevel) {
    uint256 totalPower = _getUserStakePower(user);
    if (totalPower < BRONZE_STAKE_LEVEL) {
      return StakeLevel.BRONZE;
    } else if (totalPower < SILVER_STAKE_LEVEL) {
      return StakeLevel.SILVER;
    } else if (totalPower < GOLD_STAKE_LEVEL) {
      return StakeLevel.GOLD;
    } else {
      return StakeLevel.PLATINUM;
    }
  }

  function getUserStakePower(address user) external view returns (uint256) {
    return _getUserStakePower(user);
  }

  // ====================================================== INTERNAL FUNCTIONS ================================================

  function _getUserTotalStaked(address user) internal view returns (uint256) {
    return
      userstakedAmounts[user][Duration.NONE] +
      userstakedAmounts[user][Duration.THREE_MONTHS] +
      userstakedAmounts[user][Duration.SIX_MONTHS] +
      userstakedAmounts[user][Duration.TWELVE_MONTHS];
  }

  function _getUserStakePower(address user) internal view returns (uint256) {
    return
      (userstakedAmounts[user][Duration.NONE] * 1) +
      (userstakedAmounts[user][Duration.THREE_MONTHS] * 2) +
      (userstakedAmounts[user][Duration.SIX_MONTHS] * 3) +
      (userstakedAmounts[user][Duration.TWELVE_MONTHS] * 4);
  }

  function _clearUserStakedAmounts(address user) internal {
    userstakedAmounts[user][Duration.NONE] = 0;
    userstakedAmounts[user][Duration.THREE_MONTHS] = 0;
    userstakedAmounts[user][Duration.SIX_MONTHS] = 0;
    userstakedAmounts[user][Duration.TWELVE_MONTHS] = 0;
  }

  // ====================================================== ADMIN FUNCTIONS ================================================
  function updateStakeLevelThreshold(StakeLevel stakeLevel, uint32 threshold) external onlyOwner {
    if (stakeLevel == StakeLevel.BRONZE) {
      BRONZE_STAKE_LEVEL = threshold;
    } else if (stakeLevel == StakeLevel.SILVER) {
      SILVER_STAKE_LEVEL = threshold;
    } else if (stakeLevel == StakeLevel.GOLD) {
      GOLD_STAKE_LEVEL = threshold;
    }
  }
}
