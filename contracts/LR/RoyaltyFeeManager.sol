// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165, IERC2981} from '@openzeppelin/contracts/interfaces/IERC2981.sol';

import {IRoyaltyFeeManager} from '../interfaces/IRoyaltyFeeManager.sol';
import {IRoyaltyEngine} from '../interfaces/IRoyaltyEngine.sol';

/**
 * @title RoyaltyFeeManager
 * @notice handles royalty fees
 */
contract RoyaltyFeeManager is IRoyaltyFeeManager, Ownable {
  // https://eips.ethereum.org/EIPS/eip-2981
  bytes4 public constant INTERFACE_ID_ERC2981 = 0x2a55205a;

  IRoyaltyEngine public royaltyEngine;

  event NewRoyaltyEngine(address newEngine);

  /**
   * @notice Constructor
   * @param _royaltyEngine address of the RoyaltyEngine
   */
  constructor(address _royaltyEngine) {
    royaltyEngine = IRoyaltyEngine(_royaltyEngine);
  }

  /**
   * @notice Calculate royalty fees and get recipients
   * @param collection address of the NFT contract
   * @param tokenId tokenId
   * @param amount amount to transfer
   */
  function calculateRoyaltyFeesAndGetRecipients(
    address collection,
    uint256 tokenId,
    uint256 amount
  ) external override returns (address[] memory, uint256[] memory) {
    address[] memory recipients;
    uint256[] memory royaltyAmounts;
    // check if the collection supports IERC2981
    if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC2981)) {
      (recipients[0], royaltyAmounts[0]) = IERC2981(collection).royaltyInfo(tokenId, amount);
    } else {
      // lookup from royaltyregistry.eth
      (recipients, royaltyAmounts) = royaltyEngine.getRoyalty(collection, tokenId, amount);
    }
    return (recipients, royaltyAmounts);
  }

  function updateRoyaltyEngine(address _royaltyEngine) external onlyOwner {
    royaltyEngine = IRoyaltyEngine(_royaltyEngine);
    emit NewRoyaltyEngine(_royaltyEngine);
  }
}