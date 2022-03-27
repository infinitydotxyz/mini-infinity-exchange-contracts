// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/interfaces/IERC165.sol';
import {IFeeManager, FeeParty} from '../interfaces/IFeeManager.sol';
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
  FeeParty PARTY_NAME = FeeParty.COLLECTORS;
  uint32 public MAX_COLL_FEE_BPS = 7500; // default
  address public immutable COLLECTORS_FEE_REGISTRY;

  event NewMaxBPS(uint16 newBps);

  /**
   * @notice Constructor
   * @param _collectorsFeeRegistry address of the collectors fee registry
   */
  constructor(address _collectorsFeeRegistry) {
    COLLECTORS_FEE_REGISTRY = _collectorsFeeRegistry;
  }

  /**
   * @notice Calculate collectors fees and get recipients
   * @param collection address of the NFT contract
   * @param amount sale price
   */
  function calcFeesAndGetRecipients(
    address,
    address collection,
    uint256,
    uint256 amount
  )
    external
    view
    override
    returns (
      FeeParty,
      address[] memory,
      uint256[] memory
    )
  {
    address[] memory recipients;
    uint256[] memory amounts;

    // check if collection is setup for fee share
    (, recipients[0], , amounts[0]) = _getCollectorsFeeInfo(collection, amount);

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
    IFeeRegistry(COLLECTORS_FEE_REGISTRY).registerFeeDestination(collection, msg.sender, feeDestination, bps);
  }

  // ============================================== INTERNAL FUNCTIONS ==============================================

   function _getCollectorsFeeInfo(
    address collection,
    uint256 amount
  )
    internal
    view
    returns (
      address,
      address,
      uint32,
      uint256
    )
  {
    (address setter, address destination, uint32 bps) = IFeeRegistry(COLLECTORS_FEE_REGISTRY).getFeeInfo(collection);
    uint256 collectorsFee = (bps * amount) / 10000;
    return (setter, destination, bps, collectorsFee);
  }

  // ============================================== VIEW FUNCTIONS ==============================================

  /**
   * @notice Calculate collectors fee for a collection address and return info
   * @param collection collection address
   * @param amount amount
   * @return setter, destination, bps and amount in this order
   */
  function getCollectorsFeeInfo(
    address collection,
    uint256 amount
  )
    external
    view
    returns (
      address,
      address,
      uint32,
      uint256
    )
  {
    return _getCollectorsFeeInfo(collection, amount);
  }

  // ===================================================== ADMIN FUNCTIONS =====================================================

  function setMaxBpsForFeeShare(uint16 _maxBps) external onlyOwner {
    MAX_COLL_FEE_BPS = _maxBps;
    emit NewMaxBPS(_maxBps);
  }
}
