// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {INFTTransferManager} from '../interfaces/INFTTransferManager.sol';

/**
 * @title NonCompliantNFTTransferManager.sol
 * @notice It allows the transfer of ERC721 tokens without safeTransferFrom.
 */
contract NonCompliantNFTTransferManager is INFTTransferManager {
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
   */
  function transferNFT(
    address collection,
    address from,
    address to,
    uint256 tokenId,
    uint256
  ) external override {
    require(msg.sender == INFINITY_EXCHANGE, 'Transfer: Only Infinity Exchange');
    IERC721(collection).transferFrom(from, to, tokenId);
  }
}
