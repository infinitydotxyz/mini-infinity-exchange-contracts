// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IInfinityFeeDistributor} from '../interfaces/IInfinityFeeDistributor.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IFeeManager} from '../interfaces/IFeeManager.sol';
import {IExecutionStrategy} from '../interfaces/IExecutionStrategy.sol';

/**
 * @title InfinityFeeDistributor
 * @notice distributes fees to all parties: protocol, seller, creators, curators, collectors
 */
contract InfinityFeeDistributor is IInfinityFeeDistributor, Ownable {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _feeManagers;
  address public protocolFeeRecipient;
  string public PARTY_NAME = 'protocol';

  event FeeManagerAdded(address indexed managerAddress);
  event FeeManagerRemoved(address indexed managerAddress);
  event NewProtocolFeeRecipient(address indexed protocolFeeRecipient);

  event FeeDistributed(
    string partyName,
    address indexed collection,
    uint256 indexed tokenId,
    address indexed recipient,
    address currency,
    uint256 amount
  );

  /**
   * @notice Constructor
   * @param _protocolFeeRecipient protocol fee recipient
   */
  constructor(address _protocolFeeRecipient) {
    protocolFeeRecipient = _protocolFeeRecipient;
  }

  function distributeFees(
    address strategy,
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from,
    address to,
    uint256 minPercentageToAsk
  ) external override {
    uint256 remainingAmount = amount;

    // protocol fee
    remainingAmount -= _disburseFeesToProtocol(strategy, amount, collection, tokenId, currency, from);

    // other party fees
    remainingAmount -= _disburseFeesToParties(amount, collection, tokenId, currency, from);

    // check min ask is met
    require((remainingAmount * 10000) >= (minPercentageToAsk * amount), 'Fees: Higher than expected');

    // transfer final amount (post-fees) to seller
    IERC20(currency).safeTransferFrom(from, to, remainingAmount);
  }

  // returns protocol fees
  function _disburseFeesToProtocol(
    address strategy,
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 protocolFeeAmount = _calculateProtocolFee(strategy, amount);
    if (protocolFeeRecipient != address(0) && protocolFeeAmount != 0) {
      IERC20(currency).safeTransferFrom(from, protocolFeeRecipient, protocolFeeAmount);
      emit FeeDistributed(PARTY_NAME, collection, tokenId, protocolFeeRecipient, currency, protocolFeeAmount);
    }
    return protocolFeeAmount;
  }

  // disburses fees to parties like collectors, creators, curators et and returns the disbursed amount
  function _disburseFeesToParties(
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 partyFees = 0;
    // for each party
    for (uint256 i = 0; i < _feeManagers.length(); i++) {
      IFeeManager feeManager = IFeeManager(_feeManagers.at(i));
      (string memory partyName, address[] memory feeRecipients, uint256[] memory feeAmounts) = feeManager
        .calculateFeesAndGetRecipients(collection, tokenId, amount);

      // disburse and get amount disubrsed
      partyFees += _disburseFeesToParty(partyName, collection, tokenId, feeRecipients, feeAmounts, currency, from);
    }
    return partyFees;
  }

  // disburses fees to a party like collectors and returns the disbursed amount
  function _disburseFeesToParty(
    string memory partyName,
    address collection,
    uint256 tokenId,
    address[] memory feeRecipients,
    uint256[] memory feeAmounts,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 partyFees = 0;
    uint256 numRecipients = feeRecipients.length;
    for (uint256 i = 0; i < numRecipients; i++) {
      if (feeRecipients[i] != address(0) && feeAmounts[i] != 0) {
        IERC20(currency).safeTransferFrom(from, feeRecipients[i], feeAmounts[i]);
        partyFees += feeAmounts[i];

        emit FeeDistributed(partyName, collection, tokenId, feeRecipients[i], currency, feeAmounts[i]);
      }
    }
    return partyFees;
  }

  /**
   * @notice Calculate protocol fee for an execution strategy
   * @param executionStrategy strategy
   * @param amount amount to transfer
   */
  function _calculateProtocolFee(address executionStrategy, uint256 amount) internal view returns (uint256) {
    uint256 protocolFee = IExecutionStrategy(executionStrategy).viewProtocolFee();
    return (protocolFee * amount) / 10000;
  }

  /**
   * @notice Update protocol fee recipient
   * @param _protocolFeeRecipient new recipient for protocol fees
   */
  function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
    protocolFeeRecipient = _protocolFeeRecipient;
    emit NewProtocolFeeRecipient(_protocolFeeRecipient);
  }

  /**
   * @notice Adds a FeeManager
   * @param managerAddress address of the manager
   */
  function addFeeManager(address managerAddress) external onlyOwner {
    require(!_feeManagers.contains(managerAddress), 'FeeManager: Already added');
    _feeManagers.add(managerAddress);

    emit FeeManagerAdded(managerAddress);
  }

  /**
   * @notice Remove a FeeManager
   * @param managerAddress managerAddress address of the manager to remove
   */
  function removeFeeManager(address managerAddress) external onlyOwner {
    require(_feeManagers.contains(managerAddress), 'FeeManager: Not found');
    _feeManagers.remove(managerAddress);

    emit FeeManagerRemoved(managerAddress);
  }

  /**
   * @notice Returns if a FeeManager was whitelisted
   * @param managerAddress address of the manager
   */
  function isFeeManagerAdded(address managerAddress) external view returns (bool) {
    return _feeManagers.contains(managerAddress);
  }

  /**
   * @notice number of community fee managers
   */
  function numFeeManagers() external view returns (uint256) {
    return _feeManagers.length();
  }

  /**
   * @notice See FeeManagers
   * @param cursor cursor (should start at 0 for first request)
   * @param size size of the response (e.g., 50)
   */
  function viewFeeManagers(uint256 cursor, uint256 size) external view returns (address[] memory, uint256) {
    uint256 length = size;

    if (length > _feeManagers.length() - cursor) {
      length = _feeManagers.length() - cursor;
    }

    address[] memory feeManagers = new address[](length);

    for (uint256 i = 0; i < length; i++) {
      feeManagers[i] = _feeManagers.at(cursor + i);
    }

    return (feeManagers, cursor + length);
  }
}
