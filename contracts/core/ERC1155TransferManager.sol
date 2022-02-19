// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC1155} from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import {INFTTransferManager} from '../interfaces/INFTTransferManager.sol';

/**
 * @title ERC1155TransferManager
 */
contract ERC1155TransferManager is INFTTransferManager {
  address public immutable INFINITY_EXCHANGE;

  /**
   * @notice Constructor
   * @param _infinityExchange address of the Infinity exchange
   */
  constructor(address _infinityExchange) {
    INFINITY_EXCHANGE = _infinityExchange;
  }

  /**
   * @notice Transfer ERC1155 token(s)
   * @param collection address of the collection
   * @param from address of the sender
   * @param to address of the recipient
   * @param tokenId tokenId
   * @param amount amount of tokens (1 and more for ERC1155)
   */
  function transferNFT(
    address collection,
    address from,
    address to,
    uint256 tokenId,
    uint256 amount
  ) external override {
    require(msg.sender == INFINITY_EXCHANGE, 'Transfer: Only Infinity Exchange');
    // https://docs.openzeppelin.com/contracts/3.x/api/token/erc1155#IERC1155-safeTransferFrom-address-address-uint256-uint256-bytes-
    IERC1155(collection).safeTransferFrom(from, to, tokenId, amount, '');
  }
}
