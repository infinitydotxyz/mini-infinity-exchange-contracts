// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165, IERC2981} from '@openzeppelin/contracts/interfaces/IERC2981.sol';
import {IFeeManager} from '../interfaces/IFeeManager.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';
import {IOwnable} from '../interfaces/IOwnable.sol';
import {IFeeRegistry} from '../interfaces/IFeeRegistry.sol';

/**
 * @title CollectorsFeeManager
 * @notice handles fee distribution to collectors of an NFT collection
 */

contract CollectorsFeeManager is IFeeManager, Ownable {
  // ERC721 interfaceID
  bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  // ERC1155 interfaceID
  bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
  string public PARTY_NAME = 'collectors';
  uint32 public MAX_COLL_FEE_BPS = 10000; // default
  address public immutable collectorsFeeRegistry;

  event NewMaxBPS(uint32 newBps);

  /**
   * @notice Constructor
   * @param _collectorsFeeRegistry address of the collectors fee registry
   */
  constructor(address _collectorsFeeRegistry) {
    collectorsFeeRegistry = _collectorsFeeRegistry;
  }

  /**
   * @notice Calculate collectors fees and get recipients
   * @param strategy address of the execution strategy
   * @param collection address of the NFT contract
   * @param amount sale price
   */
  function calcFeesAndGetRecipients(
    address strategy,
    address collection,
    uint256,
    uint256 amount
  )
    external
    view
    override
    returns (
      string memory,
      address[] memory,
      uint256[] memory
    )
  {
    address[] memory recipients;
    uint256[] memory amounts;

    // check if collection is setup for fee share
    (, recipients[0], , amounts[0]) = getCollectorsFeeInfo(strategy, collection, amount);

    return (PARTY_NAME, recipients, amounts);
  }

  /**
   * @notice supports rev sharing for a collection via self service of
   * owner/admin of collection or by owner of this contract
   * @param collection collection address
   * @param feeDestination fee destination address
   * @param bps bps relative to protocol fee; 10000 bps = 100%; 50000 bps = 50%
   * e.g a bps set to 10000 would allow the collection to earn the same fees as the protocol
   * e.g a bps set to 5000 would allow the collection to earn the 50% of the protocol fees
   * e.g a bps set to 100 would allow the collection to earn the 1% of the protocol fees
   */
  function setupCollectionForFeeShare(
    address collection,
    address feeDestination,
    uint32 bps
  ) external {
    require(feeDestination != address(0), 'fee destination cant be 0x0');
    require(
      (IERC165(collection).supportsInterface(INTERFACE_ID_ERC721) ||
        IERC165(collection).supportsInterface(INTERFACE_ID_ERC1155)),
      'Collection is not ERC721/ERC1155'
    );

    // see if collection has admin
    address collAdmin;
    try IOwnable(collection).owner() returns (address _owner) {
      collAdmin = _owner;
    } catch {
      try IOwnable(collection).admin() returns (address _admin) {
        collAdmin = _admin;
      } catch {
        collAdmin = address(0);
      }
    }

    require(msg.sender == owner() || msg.sender == collAdmin, 'Unauthorized');
    require(bps < MAX_COLL_FEE_BPS, 'bps too high');

    // setup
    IFeeRegistry(collectorsFeeRegistry).registerFeeDestination(collection, msg.sender, feeDestination, bps);
  }

  /**
   * @notice Update owner of collector fee registry
   * @dev Can be used for migration of this fee manager contract
   * @param _owner new owner address
   */
  function updateOwnerOfCollectorsFeeRegistry(address _owner) external onlyOwner {
    Ownable(collectorsFeeRegistry).transferOwnership(_owner);
  }

  function setMaxBpsForFeeShare(uint32 _maxBps) external onlyOwner {
    MAX_COLL_FEE_BPS = _maxBps;
    emit NewMaxBPS(_maxBps);
  }

  /**
   * @notice Calculate protocol fee for an execution strategy
   * @param executionStrategy strategy
   * @param amount amount to transfer
   */
  function _calculateProtocolFee(address executionStrategy, uint256 amount) internal view returns (uint256) {
    uint256 protocolFee = IExecutionStrategy(executionStrategy).getProtocolFee();
    return (protocolFee * amount) / 10000;
  }

  /**
   * @notice Calculate collectors fee for a collection address and return info
   * @param collection collection address
   * @param amount amount
   * @return setter, destination, bps and amount in this order
   */
  function getCollectorsFeeInfo(
    address strategy,
    address collection,
    uint256 amount
  )
    public
    view
    returns (
      address,
      address,
      uint32,
      uint256
    )
  {
    (address setter, address destination, uint32 bps) = IFeeRegistry(collectorsFeeRegistry).getFeeInfo(collection);
    uint256 protocolFee = _calculateProtocolFee(strategy, amount);
    uint256 collectorsFee = (bps * protocolFee) / 10000;
    return (setter, destination, bps, collectorsFee);
  }
}
