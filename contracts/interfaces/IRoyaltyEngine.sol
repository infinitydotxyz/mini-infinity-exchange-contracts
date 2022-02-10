// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IRoyaltyEngine {
  function getRoyalty(
    address tokenAddress,
    uint256 tokenId,
    uint256 value
  ) external returns (address[] memory recipients, uint256[] memory amounts);
}
