// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IInfinityFeeDistributor {
  function distributeFees(
    address strategy,
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from,
    address to,
    uint256 minBpsToSeller
  ) external;
}
