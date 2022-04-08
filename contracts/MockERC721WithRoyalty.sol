// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import {ERC721URIStorage} from '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {IERC2981} from '@openzeppelin/contracts/interfaces/IERC2981.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract MockERC721WithRoyalty is ERC721URIStorage, IERC2981, Ownable {
  uint256 numMints;
  uint16 royaltyBps;

  constructor(string memory name, string memory symbol) ERC721(name, symbol) {
    for (uint256 i = 0; i < 100; i++) {
      _safeMint(msg.sender, numMints++);
    }
  }

  function setRoyaltyBps(uint16 bps) external onlyOwner {
    royaltyBps = bps;
  }

  function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
    uint256 royalty = (salePrice * royaltyBps) / 10000;
    return (owner(), royalty);
  }
}
