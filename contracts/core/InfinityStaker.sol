// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Pausable} from '@openzeppelin/contracts/security/Pausable.sol';
import {IStaker, Duration, StakeLevel} from '../interfaces/IStaker.sol';
import 'hardhat/console.sol'; // todo: remove this

contract InfinityStaker is IStaker, Ownable, Pausable {
  using SafeERC20 for IERC20;
  mapping(address => mapping(Duration => uint256)) public userstakedAmounts;
  address INFINITY_TOKEN;
  address INFINITY_TREASURY;
  uint16 public BRONZE_STAKE_LEVEL = 1000;
  uint16 public SILVER_STAKE_LEVEL = 5000;
  uint16 public GOLD_STAKE_LEVEL = 10000;
  uint16 public THREE_MONTH_PENALTY = 3;
  uint16 public SIX_MONTH_PENALTY = 6;
  uint16 public TWELVE_MONTH_PENALTY = 12;

  event Staked(address indexed user, uint256 amount, Duration duration);
  event Locked(address indexed user, uint256 amount, Duration duration);
  event DurationChanged(address indexed user, uint256 amount, Duration oldDuration, Duration newDuration);
  event UnStaked(address indexed user, uint256 amount);
  event RageQuit(address indexed user, uint256 totalStaked, uint256 totalToUser);

  constructor(address _tokenAddress, address _infinityTreasury) {
    INFINITY_TOKEN = _tokenAddress;
    INFINITY_TREASURY = _infinityTreasury;
  }

  // Fallback
  fallback() external payable {}

  receive() external payable {}

  // =================================================== USER FUNCTIONS =======================================================
  function stake(address user, uint256 amount, Duration duration) external whenNotPaused {
    require(amount != 0, 'stake amount cant be 0');
    require(IERC20(INFINITY_TOKEN).balanceOf(user) >= amount, 'insufficient balance to stake');

    // update storage
    userstakedAmounts[user][duration] += amount;
    // perform transfer
    IERC20(INFINITY_TOKEN).safeTransferFrom(user, address(this), amount);
    // emit event
    emit Staked(user, amount, duration);
  }

  function lock(address user, uint256 amount, Duration duration) external whenNotPaused {
    require(amount != 0, 'lock amount cant be 0');
    require(userstakedAmounts[user][Duration.NONE] >= amount, 'insufficient balance to lock');
    require(duration != Duration.NONE, 'cant lock for duration NONE');

    // update storage
    userstakedAmounts[user][Duration.NONE] -= amount;
    userstakedAmounts[user][duration] += amount;
    // emit event
    emit Locked(user, amount, duration);
  }

  function changeDuration(
    address user,
    uint256 amount,
    Duration oldDuration,
    Duration newDuration
  ) external whenNotPaused {
    require(amount != 0, 'amount cant be 0');
    require(userstakedAmounts[user][oldDuration] >= amount, 'insufficient staked amount to change duration');

    // update storage
    userstakedAmounts[user][oldDuration] -= amount;
    userstakedAmounts[user][newDuration] += amount;
    // emit event
    emit DurationChanged(user, amount, oldDuration, newDuration);
  }

  function unstake(address user, uint256 amount) external whenNotPaused {
    require(amount != 0, 'stake amount cant be 0');
    require(userstakedAmounts[user][Duration.NONE] >= amount, 'insufficient balance to unstake');

    // update storage
    userstakedAmounts[user][Duration.NONE] -= amount;
    // perform transfer
    IERC20(INFINITY_TOKEN).safeTransferFrom(address(this), user, amount);
    // emit event
    emit UnStaked(user, amount);
  }

  function rageQuit() external {
    uint256 noLock = userstakedAmounts[msg.sender][Duration.NONE];
    uint256 threeMonthLock = userstakedAmounts[msg.sender][Duration.THREE_MONTHS];
    uint256 sixMonthLock = userstakedAmounts[msg.sender][Duration.SIX_MONTHS];
    uint256 twelveMonthLock = userstakedAmounts[msg.sender][Duration.TWELVE_MONTHS];
    uint256 totalStaked = noLock + threeMonthLock + sixMonthLock + twelveMonthLock;
    require(totalStaked >= 0, 'nothing staked to rage quit');
    uint256 totalToUser = noLock +
      threeMonthLock /
      THREE_MONTH_PENALTY +
      sixMonthLock /
      SIX_MONTH_PENALTY +
      twelveMonthLock /
      TWELVE_MONTH_PENALTY;

    // update storage
    _clearUserStakedAmounts(msg.sender);
    // perform transfers
    IERC20(INFINITY_TOKEN).safeTransfer(msg.sender, totalToUser);
    IERC20(INFINITY_TOKEN).safeTransfer(INFINITY_TREASURY, totalStaked - totalToUser);
    // emit event
    emit RageQuit(msg.sender, totalStaked, totalToUser);
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
  
  function rescueTokens(
    address destination,
    address currency,
    uint256 amount
  ) external onlyOwner {
    IERC20(currency).safeTransfer(destination, amount);
  }

  function rescueETH(address destination) external payable onlyOwner {
    (bool sent, ) = destination.call{value: msg.value}('');
    require(sent, 'Failed to send Ether');
  }
  
  function updateStakeLevelThreshold(StakeLevel stakeLevel, uint16 threshold) external onlyOwner {
    if (stakeLevel == StakeLevel.BRONZE) {
      BRONZE_STAKE_LEVEL = threshold;
    } else if (stakeLevel == StakeLevel.SILVER) {
      SILVER_STAKE_LEVEL = threshold;
    } else if (stakeLevel == StakeLevel.GOLD) {
      GOLD_STAKE_LEVEL = threshold;
    }
  }

  function updatePenalties(
    uint16 threeMonthPenalty,
    uint16 sixMonthPenalty,
    uint16 twelveMonthPenalty
  ) external onlyOwner {
    THREE_MONTH_PENALTY = threeMonthPenalty;
    SIX_MONTH_PENALTY = sixMonthPenalty;
    TWELVE_MONTH_PENALTY = twelveMonthPenalty;
  }

  function updateInfinityTreasury(address _infinityTreasury) external onlyOwner {
    INFINITY_TREASURY = _infinityTreasury;
  }
}
