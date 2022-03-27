// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IFeeManager, FeeParty} from '../interfaces/IFeeManager.sol';
import {IOwnable} from '../interfaces/IOwnable.sol';

/**
 * @title CuratorsFeeManager
 * @notice handles fee distribution to curators of collections
 */

contract CuratorsFeeManager is IFeeManager, Ownable {
  FeeParty PARTY_NAME = FeeParty.CURATORS;
  uint32 public MAX_CURATOR_FEE_BPS = 7500; // default
  address CURATOR_FEE_TREASURY;

  event NewMaxBPS(uint16 newBps);
  event NewCuratorFeeTreasury(address treasury);

  /**
   * @notice Constructor
   * @param _curatorFeeTreasury destination for curator fees
   */
  constructor(address _curatorFeeTreasury) {
    CURATOR_FEE_TREASURY = _curatorFeeTreasury;
  }

  /**
   * @notice Calculate fees and get recipients
   * @param amount sale price
   */
  function calcFeesAndGetRecipients(
    address,
    address,
    uint256,
    uint256 amount
  )
    external
    view
    override
    returns (
      FeeParty,
      address[] memory,
      uint256[] memory
    )
  {
    address[] memory recipients;
    uint256[] memory amounts;
    (recipients[0], amounts[0]) = (CURATOR_FEE_TREASURY, (amount * MAX_CURATOR_FEE_BPS) / 10000);

    return (PARTY_NAME, recipients, amounts);
  }

  // ================================================= ADMIN FUNCTIONS =================================================
  function setMaxBpsForFeeShare(uint16 _maxBps) external onlyOwner {
    MAX_CURATOR_FEE_BPS = _maxBps;
    emit NewMaxBPS(_maxBps);
  }

  function updateCuratorFeeTreasury(address treasury) external onlyOwner {
    CURATOR_FEE_TREASURY = treasury;
    emit NewCuratorFeeTreasury(treasury);
  }
}
