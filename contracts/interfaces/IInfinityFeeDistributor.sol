// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfinityFeeDistributor {
  function distributeFees(
    uint256 amount,
    address currency,
    address from,
    address to,
    uint256 minBpsToSeller,
    address execStrategy, 
    address collection,
    uint256 tokenId
  ) external;
}
