// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IFeeRegistry} from '../interfaces/IFeeRegistry.sol';

/**
 * @title CollectorsFeeRegistry
 * @notice owned by CollectorsFeeManager; serves as a data registry
 */
contract CollectorsFeeRegistry is IFeeRegistry, Ownable {
  address COLLECTION_FEE_MANAGER;
  struct FeeInfo {
    address setter;
    address destination;
    uint16 bps;
  }

  mapping(address => FeeInfo) private _collectorsFeeInfo;

  event CollectorsFeeUpdate(
    address indexed collection,
    address indexed setter,
    address indexed destination,
    uint16 bps
  );

  event CollectionFeeManagerUpdated(address indexed manager);

  /**
   * @notice Update collectors fee for collection
   * @param collection address of the NFT contract
   * @param setter address that sets the receiver
   * @param destination receiver for the fee
   * @param bps fee (500 = 5%, 1,000 = 10%)
   */
  function registerFeeDestination(
    address collection,
    address setter,
    address destination,
    uint16 bps
  ) external override onlyOwner {
    require(msg.sender == COLLECTION_FEE_MANAGER, 'Collection Registry: Only collection fee manager');
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
      uint16
    )
  {
    return (
      _collectorsFeeInfo[collection].setter,
      _collectorsFeeInfo[collection].destination,
      _collectorsFeeInfo[collection].bps
    );
  }

  // ===================================================== ADMIN FUNCTIONS =====================================================

  function updateCollectionFeeManager(address manager) external onlyOwner {
    COLLECTION_FEE_MANAGER = manager;
    emit CollectionFeeManagerUpdated(manager);
  }
}
