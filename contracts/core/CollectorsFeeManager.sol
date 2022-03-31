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
  bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
  FeeParty PARTY_NAME = FeeParty.COLLECTORS;
  uint16 public MAX_COLL_FEE_BPS = 50;
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
    (, recipients, , amounts) = _getCollectorsFeeInfo(collection, amount);

    return (PARTY_NAME, recipients, amounts);
  }

  /**
   * @notice supports rev sharing for a collection via self service of
   * owner/admin of collection or by owner of this contract
   * @param collection collection address
   * @param feeDestinations fee destinations
   * @param bpsSplits bpsSplits between destinations
   */
  function setupCollectionForFeeShare(
    address collection,
    address[] calldata feeDestinations,
    uint16[] calldata bpsSplits
  ) external {
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
    // check total bps
    uint32 totalBps = 0;
    for (uint256 i= 0; i< bpsSplits.length;) {
      totalBps += bpsSplits[i];
      unchecked {
        ++i;
      }
    }
    require(totalBps < MAX_COLL_FEE_BPS, 'bps too high');

    // setup
    IFeeRegistry(COLLECTORS_FEE_REGISTRY).registerFeeDestinations(collection, msg.sender, feeDestinations, bpsSplits);
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
      address[] memory,
      uint16[] memory,
      uint256[] memory
    )
  {
    (address setter, address[] memory destinations, uint16[] memory bpsSplits) = IFeeRegistry(COLLECTORS_FEE_REGISTRY).getFeeInfo(collection);
    uint256[] memory collectorsFees = new uint256[](bpsSplits.length);
    for (uint256 i = 0; i < bpsSplits.length;) {
      collectorsFees[i] = (bpsSplits[i] * amount) / 10000;
      unchecked {
        ++i;
      }
    }
    return (setter, destinations, bpsSplits, collectorsFees);
  }

  // ============================================== VIEW FUNCTIONS ==============================================

  /**
   * @notice Calculate collectors fee for a collection address and return info
   * @param collection collection address
   * @param amount amount
   */
  function getCollectorsFeeInfo(
    address collection,
    uint256 amount
  )
    external
    view
    returns (
      address,
      address[] memory,
      uint16[] memory,
      uint256[] memory
    )
  {
    return _getCollectorsFeeInfo(collection, amount);
  }

  // ===================================================== ADMIN FUNCTIONS =====================================================

  function setMaxCollectorFeeBps(uint16 _maxBps) external onlyOwner {
    MAX_COLL_FEE_BPS = _maxBps;
    emit NewMaxBPS(_maxBps);
  }
}
