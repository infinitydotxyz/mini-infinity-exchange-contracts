// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IFeeRegistry} from '../interfaces/IFeeRegistry.sol';

/**
 * @title InfinityCollectorsFeeRegistry
 */
contract InfinityCollectorsFeeRegistry is IFeeRegistry, Ownable {
  address COLLECTORS_FEE_MANAGER;
  struct FeeInfo {
    address setter;
    address[] destinations;
    uint16[] bpsSplits;
  }

  mapping(address => FeeInfo) private _collectorsFeeInfo;

  event CollectorsFeeUpdate(
    address indexed collection,
    address indexed setter,
    address[] destination,
    uint16[] bpsSplits
  );

  event CollectorsFeeManagerUpdated(address indexed manager);

  /**
   * @notice Update collectors fee for collection
   * @param collection address of the NFT contract
   * @param setter address that sets destinations
   * @param destinations receivers for the fee
   * @param bpsSplits fee (500 = 5%, 1,000 = 10%)
   */
  function registerFeeDestinations(
    address collection,
    address setter,
    address[] calldata destinations,
    uint16[] calldata bpsSplits
  ) external override onlyOwner {
    require(msg.sender == COLLECTORS_FEE_MANAGER, 'Collectors Fee Registry: Only collector fee manager');
    _collectorsFeeInfo[collection] = FeeInfo({setter: setter, destinations: destinations, bpsSplits: bpsSplits});
    emit CollectorsFeeUpdate(collection, setter, destinations, bpsSplits);
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
      address[] memory,
      uint16[] memory
    )
  {
    return (
      _collectorsFeeInfo[collection].setter,
      _collectorsFeeInfo[collection].destinations,
      _collectorsFeeInfo[collection].bpsSplits
    );
  }

  // ===================================================== ADMIN FUNCTIONS =====================================================

  function updateCollectorsFeeManager(address manager) external onlyOwner {
    COLLECTORS_FEE_MANAGER = manager;
    emit CollectorsFeeManagerUpdated(manager);
  }
}
