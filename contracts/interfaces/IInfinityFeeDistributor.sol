// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfinityFeeDistributor {
  function getFeeDiscountBps(address user) external view returns (uint16);

  function distributeFees(
    address seller,
    address buyer,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address execComplication
  ) external;
}
