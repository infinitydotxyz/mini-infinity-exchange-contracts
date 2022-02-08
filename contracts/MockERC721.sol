// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.9;
import {ERC721URIStorage} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract MockERC721 is ERC721URIStorage {
  constructor() ERC721('MockERC721', 'MCK721') {}
}