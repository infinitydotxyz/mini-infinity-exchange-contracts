// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165, IERC2981} from '@openzeppelin/contracts/interfaces/IERC2981.sol';
import {IFeeManager, FeeParty} from '../interfaces/IFeeManager.sol';
import {IOwnable} from '../interfaces/IOwnable.sol';
import {IRoyaltyEngine} from '../interfaces/IRoyaltyEngine.sol';
import {IFeeRegistry} from '../interfaces/IFeeRegistry.sol';

/**
 * @title InfinityCreatorsFeeManager
 * @notice handles creator fees aka royalties
 */
contract InfinityCreatorsFeeManager is IFeeManager, Ownable {
  bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
  bytes4 public constant INTERFACE_ID_ERC2981 = 0x2a55205a;
  FeeParty public PARTY_NAME = FeeParty.CREATORS;
  IRoyaltyEngine public royaltyEngine;
  uint16 public MAX_CREATOR_FEE_BPS = 1000;
  address public immutable CREATORS_FEE_REGISTRY;

  event NewRoyaltyEngine(address newEngine);
  event NewMaxBPS(uint16 newBps);

  /**
   * @notice Constructor
   */
  constructor(address _royaltyEngine, address _creatorsFeeRegistry) {
    royaltyEngine = IRoyaltyEngine(_royaltyEngine);
    CREATORS_FEE_REGISTRY = _creatorsFeeRegistry;
  }

  /**
   * @notice Calculate creator fees and get recipients
   * @param collection address of the NFT contract
   * @param tokenId tokenId
   * @param amount sale amount
   */
  function calcFeesAndGetRecipients(
    address,
    address collection,
    uint256 tokenId,
    uint256 amount
  )
    external
    override
    returns (
      FeeParty,
      address[] memory,
      uint256[] memory
    )
  {
    address[] memory recipients;
    uint256[] memory amounts;

    // check if the creators fee is registered
    (, recipients, , amounts) = _getCreatorsFeeInfo(collection, amount);
    if (recipients.length > 0) {
      return (PARTY_NAME, recipients, amounts);
    } else if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC2981)) {
      (recipients[0], amounts[0]) = IERC2981(collection).royaltyInfo(tokenId, amount);
    } else {
      // lookup from royaltyregistry.eth
      (recipients, amounts) = royaltyEngine.getRoyalty(collection, tokenId, amount);
    }
    return (PARTY_NAME, recipients, amounts);
  }

  /**
   * @notice supports creator fee (royalty) sharing for a collection via self service of
   * owner/admin of collection or by owner of this contract
   * @param collection collection address
   * @param feeDestinations fee destinations
   * @param bpsSplits bpsSplits between destinations
   */
  function setupCollectionForCreatorFeeShare(
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

    require(msg.sender == owner() || msg.sender == collAdmin, 'unauthorized');
    // check total bps
    uint32 totalBps = 0;
    for (uint256 i = 0; i < bpsSplits.length; ) {
      totalBps += bpsSplits[i];
      unchecked {
        ++i;
      }
    }
    require(totalBps <= MAX_CREATOR_FEE_BPS, 'bps too high');

    // setup
    IFeeRegistry(CREATORS_FEE_REGISTRY).registerFeeDestinations(collection, msg.sender, feeDestinations, bpsSplits);
  }

  // ============================================== INTERNAL FUNCTIONS ==============================================

  function _getCreatorsFeeInfo(address collection, uint256 amount)
    internal
    view
    returns (
      address,
      address[] memory,
      uint16[] memory,
      uint256[] memory
    )
  {
    (address setter, address[] memory destinations, uint16[] memory bpsSplits) = IFeeRegistry(CREATORS_FEE_REGISTRY)
      .getFeeInfo(collection);
    uint256[] memory creatorsFees = new uint256[](bpsSplits.length);
    for (uint256 i = 0; i < bpsSplits.length; ) {
      creatorsFees[i] = (bpsSplits[i] * amount) / 10000;
      unchecked {
        ++i;
      }
    }
    return (setter, destinations, bpsSplits, creatorsFees);
  }

  // ============================================== VIEW FUNCTIONS ==============================================

  /**
   * @notice Calculate creators fee for a collection address and return info
   * @param collection collection address
   * @param amount amount
   */
  function getCreatorsFeeInfo(address collection, uint256 amount)
    external
    view
    returns (
      address,
      address[] memory,
      uint16[] memory,
      uint256[] memory
    )
  {
    return _getCreatorsFeeInfo(collection, amount);
  }

  // ===================================================== ADMIN FUNCTIONS =====================================================

  function setMaxCreatorFeeBps(uint16 _maxBps) external onlyOwner {
    MAX_CREATOR_FEE_BPS = _maxBps;
    emit NewMaxBPS(_maxBps);
  }

  function updateRoyaltyEngine(address _royaltyEngine) external onlyOwner {
    royaltyEngine = IRoyaltyEngine(_royaltyEngine);
    emit NewRoyaltyEngine(_royaltyEngine);
  }
}
