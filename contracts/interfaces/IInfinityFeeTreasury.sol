// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfinityFeeTreasury {
  function getFeeDiscountBps(address user) external view returns (uint16);

  function allocateFees(
    address seller,
    address buyer,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address execComplication
  ) external;

  function claimCreatorFees(address currency) external;

  function claimCuratorFees(address currency) external;

  function claimCollectorFees(address currency) external;
}
