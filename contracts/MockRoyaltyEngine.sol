// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IRoyaltyEngine} from './interfaces/IRoyaltyEngine.sol';

contract MockRoyaltyEngine is IRoyaltyEngine {
  function getRoyalty(
    address,
    uint256,
    uint256
  ) external pure returns (address[] memory recipients, uint256[] memory amounts) {
    return (recipients, amounts);
  }
}
