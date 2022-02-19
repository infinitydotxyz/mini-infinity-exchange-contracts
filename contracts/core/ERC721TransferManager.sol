// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import {INFTTransferManager} from '../interfaces/INFTTransferManager.sol';

/**
 * @title ERC721TransferManager
 */
contract ERC721TransferManager is INFTTransferManager {
  address public immutable INFINITY_EXCHANGE;

  /**
   * @notice Constructor
   * @param _infinityExchange address of the Infinity exchange
   */
  constructor(address _infinityExchange) {
    INFINITY_EXCHANGE = _infinityExchange;
  }

  /**
   * @notice Transfer ERC721 token
   * @param collection address of the collection
   * @param from address of the sender
   * @param to address of the recipient
   * @param tokenId tokenId
   * @dev For ERC721, amount is not used
   */
  function transferNFT(
    address collection,
    address from,
    address to,
    uint256 tokenId,
    uint256
  ) external override {
    require(msg.sender == INFINITY_EXCHANGE, 'Transfer: Only Infinity Exchange');
    // https://docs.openzeppelin.com/contracts/2.x/api/token/erc721#IERC721-safeTransferFrom
    IERC721(collection).safeTransferFrom(from, to, tokenId);
  }
}
