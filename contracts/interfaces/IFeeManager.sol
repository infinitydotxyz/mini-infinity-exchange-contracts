// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum FeeParty {
  PROTOCOL,
  SAFU_FUND,
  CREATORS,
  COLLECTORS,
  CURATORS
}

interface IFeeManager {
  function calcFeesAndGetRecipients(
    address complication,
    address collection,
    uint256 tokenId,
    uint256 amount
  )
    external
    returns (
      FeeParty partyName,
      address[] memory,
      uint256[] memory
    );
}
