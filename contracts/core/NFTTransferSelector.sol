// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/interfaces/IERC165.sol';

import {INFTTransferSelector} from '../interfaces/INFTTransferSelector.sol';

/**
 * @title NFTTransferSelector
 */
contract NFTTransferSelector is INFTTransferSelector, Ownable {
  // ERC721 interfaceID
  bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
  // ERC1155 interfaceID
  bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

  // Address of the transfer manager contract for ERC721 tokens
  address public immutable ERC721_TRANSFER_MANAGER;

  // Address of the transfer manager contract for ERC1155 tokens
  address public immutable ERC1155_TRANSFER_MANAGER;

  // Map collection address to transfer manager address
  mapping(address => address) public transferManagerSelectorForCollection;

  event CollectionTransferManagerAdded(address indexed collection, address indexed transferManager);
  event CollectionTransferManagerRemoved(address indexed collection);

  /**
   * @notice Constructor
   * @param _erc721TransferManager address of the ERC721 transfer manager
   * @param _erc1155transferManager address of the ERC1155 transfer manager
   */
  constructor(address _erc721TransferManager, address _erc1155transferManager) {
    ERC721_TRANSFER_MANAGER = _erc721TransferManager;
    ERC1155_TRANSFER_MANAGER = _erc1155transferManager;
  }

  /**
   * @notice Add a transfer manager for a collection
   * @param collection collection address to add specific transfer rule
   * @dev It is meant to be used for exceptions only (e.g., CryptoKitties)
   */
  function addCollectionTransferManager(address collection, address transferManager) external onlyOwner {
    require(collection != address(0), 'Owner: Collection cannot be null address');
    require(transferManager != address(0), 'Owner: TransferManager cannot be null address');

    transferManagerSelectorForCollection[collection] = transferManager;

    emit CollectionTransferManagerAdded(collection, transferManager);
  }

  /**
   * @notice Remove a transfer manager for a collection
   * @param collection collection address to remove exception
   */
  function removeCollectionTransferManager(address collection) external onlyOwner {
    require(
      transferManagerSelectorForCollection[collection] != address(0),
      'Owner: Collection has no transfer manager'
    );

    // Set it to the address(0)
    transferManagerSelectorForCollection[collection] = address(0);

    emit CollectionTransferManagerRemoved(collection);
  }

  /**
   * @notice Check the transfer manager for a token
   * @param collection collection address
   * @dev Support for ERC165 interface is checked AFTER custom implementation
   */
  function getTransferManager(address collection) external view override returns (address transferManager) {
    // Assign transfer manager (if any)
    transferManager = transferManagerSelectorForCollection[collection];

    if (transferManager == address(0)) {
      if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC721)) {
        transferManager = ERC721_TRANSFER_MANAGER;
      } else if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC1155)) {
        transferManager = ERC1155_TRANSFER_MANAGER;
      }
    }

    return transferManager;
  }
}
