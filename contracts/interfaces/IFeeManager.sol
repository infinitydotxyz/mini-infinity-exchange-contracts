// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IFeeManager {
  function calcFeesAndGetRecipient(
    address complication,
    address collection,
    uint256 amount
  )
    external
    view
    returns (
      address,
      uint256
    );
}
