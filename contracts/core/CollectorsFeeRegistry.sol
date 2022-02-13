// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IFeeRegistry} from '../interfaces/IFeeRegistry.sol';

/**
 * @title CollectorsFeeRegistry
 */
contract CollectorsFeeRegistry is IFeeRegistry, Ownable {
  struct FeeInfo {
    address setter;
    address destination;
    uint32 bps;
  }

  mapping(address => FeeInfo) private _collectorsFeeInfo;

  event CollectorsFeeUpdate(
    address indexed collection,
    address indexed setter,
    address indexed destination,
    uint32 bps
  );

  /**
   * @notice Update collectors fee for collection
   * @param collection address of the NFT contract
   * @param setter address that sets the receiver
   * @param destination receiver for the royalty fee
   * @param bps fee (500 = 5%, 1,000 = 10%)
   */
  function registerFeeDestination(
    address collection,
    address setter,
    address destination,
    uint32 bps
  ) external override onlyOwner {
    _collectorsFeeInfo[collection] = FeeInfo({setter: setter, destination: destination, bps: bps});
    emit CollectorsFeeUpdate(collection, setter, destination, bps);
  }

  /**
   * @notice View collector fee info for a collection address
   * @param collection collection address
   */
  function getFeeInfo(address collection)
    external
    view
    override
    returns (
      address,
      address,
      uint32
    )
  {
    return (
      _collectorsFeeInfo[collection].setter,
      _collectorsFeeInfo[collection].destination,
      _collectorsFeeInfo[collection].bps
    );
  }
}
