// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IRoyaltyEngine {
  function owner () external view returns ( address );
  function renounceOwnership () external;
  function royaltyRegistry () external view returns ( address );
  function transferOwnership ( address newOwner ) external;
  function initialize ( address royaltyRegistry_ ) external;
  function supportsInterface ( bytes4 interfaceId ) external view returns ( bool );
  function getRoyalty ( address tokenAddress, uint256 tokenId, uint256 value ) external returns ( address[] memory recipients, uint256[] memory amounts );
  function getRoyaltyView ( address tokenAddress, uint256 tokenId, uint256 value ) external view returns ( address[] memory recipients, uint256[] memory amounts );
}
