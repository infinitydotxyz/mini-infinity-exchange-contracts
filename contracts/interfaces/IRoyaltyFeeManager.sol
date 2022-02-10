// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRoyaltyFeeManager {
  function calculateRoyaltyFeesAndGetRecipients(
    address collection,
    uint256 tokenId,
    uint256 amount
  ) external returns (address[] memory, uint256[] memory);
}
