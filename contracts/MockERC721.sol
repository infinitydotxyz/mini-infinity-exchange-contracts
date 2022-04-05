// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import {ERC721URIStorage} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract MockERC721 is ERC721URIStorage {
  uint256 numMints = 0;

  constructor(string memory name, string memory symbol) ERC721(name, symbol) {
    for (uint256 i = 0; i < 100; i++) {
      _safeMint(msg.sender, numMints++);
    }
  }
}
