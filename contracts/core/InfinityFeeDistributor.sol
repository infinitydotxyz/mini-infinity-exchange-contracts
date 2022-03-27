// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IInfinityFeeDistributor} from '../interfaces/IInfinityFeeDistributor.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IFeeManager} from '../interfaces/IFeeManager.sol';
import {IComplication} from '../interfaces/IComplication.sol';

/**
 * @title InfinityFeeDistributor
 * @notice distributes fees to all parties: protocol, safu fund, seller, creators, curators, collectors
 */
contract InfinityFeeDistributor is IInfinityFeeDistributor, Ownable {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private _feeManagers;
  address public SAFU_FEE_RECIPIENT;
  address public PROTOCOL_FEE_RECIPIENT;
  address public INFINITY_EXCHANGE;
  string public PROTOCOL_PARTY_NAME = 'protocol';
  string public SAFU_PARTY_NAME = 'safu';
  uint256 public SAFU_FEE_BPS = 500; // default

  event FeeManagerAdded(address indexed managerAddress);
  event FeeManagerRemoved(address indexed managerAddress);
  event NewProtocolFeeRecipient(address indexed protocolFeeRecipient);
  event NewSafuFeeRecipient(address indexed safuFeeRecipient);
  event SafuFeeUpdated(uint256 newBps);

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
   * @param _safuFeeRecipient safu fee recipient
   * @param _infinityExchange infinity exchange address
   */
  constructor(address _protocolFeeRecipient, address _safuFeeRecipient, address _infinityExchange) {
    PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
    SAFU_FEE_RECIPIENT = _safuFeeRecipient;
    INFINITY_EXCHANGE = _infinityExchange;
  }

  function distributeFees(
    address seller,
    address buyer,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    uint256 minBpsToSeller,
    address execComplication
  ) external override {
    require(msg.sender == INFINITY_EXCHANGE, 'Fee distribution: Only Infinity exchange');
    uint256 remainingAmount = amount;
    // protocol fee
    remainingAmount -= _disburseFeesToProtocol(execComplication, amount, collection, tokenId, currency, seller);
    // safu fund fee
    remainingAmount -= _disburseFeesToSafuFund(amount, collection, tokenId, currency, seller);
    // other party fees
    remainingAmount -= _disburseFeesToParties(execComplication, amount, collection, tokenId, currency, seller);
    // check min bps to seller is met
    require((remainingAmount * 10000) >= (minBpsToSeller * amount), 'Fees: Higher than expected');
    // transfer final amount (post-fees) to seller
    IERC20(currency).safeTransferFrom(buyer, seller, remainingAmount);
  }

  /**
   * @notice sends protocol fees to protocol fee recipient and returns amount sent
   */
  function _disburseFeesToProtocol(
    address execComplication,
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 protocolFeeAmount = _calculateProtocolFee(execComplication, amount);
    if (PROTOCOL_FEE_RECIPIENT != address(0) && protocolFeeAmount != 0) {
      IERC20(currency).safeTransferFrom(from, PROTOCOL_FEE_RECIPIENT, protocolFeeAmount);
      emit FeeDistributed(PROTOCOL_PARTY_NAME, collection, tokenId, PROTOCOL_FEE_RECIPIENT, currency, protocolFeeAmount);
    }
    return protocolFeeAmount;
  }

  /**
   * @notice sends safu fees and returns amount sent
   */
  function _disburseFeesToSafuFund(
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 safuAmount = (SAFU_FEE_BPS * amount) / 10000;
    if (SAFU_FEE_RECIPIENT != address(0) && safuAmount != 0) {
      IERC20(currency).safeTransferFrom(from, SAFU_FEE_RECIPIENT, safuAmount);
      emit FeeDistributed(SAFU_PARTY_NAME, collection, tokenId, SAFU_FEE_RECIPIENT, currency, safuAmount);
    }
    return safuAmount;
  }

  /**
   * @notice disburses fees to parties like collectors, creators, curators etc and returns the disbursed amount
   */
  function _disburseFeesToParties(
    address execComplication,
    uint256 amount,
    address collection,
    uint256 tokenId,
    address currency,
    address from
  ) internal returns (uint256) {
    uint256 partyFees = 0;
    // for each party
    for (uint256 i = 0; i < _feeManagers.length();) {
      partyFees += _disburseFeesViaFeeManager(
        _feeManagers.at(i),
        execComplication,
        collection,
        tokenId,
        amount,
        currency,
        from
      );
      unchecked {
        ++i;
      }
    }
    return partyFees;
  }

  function _disburseFeesViaFeeManager(
    address feeManagerAddress,
    address execComplication,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    address from
  ) internal returns (uint256) {
    IFeeManager feeManager = IFeeManager(feeManagerAddress);
    (string memory partyName, address[] memory feeRecipients, uint256[] memory feeAmounts) = feeManager
      .calcFeesAndGetRecipients(execComplication, collection, tokenId, amount);
    return _disburseFeesToParty(partyName, collection, tokenId, feeRecipients, feeAmounts, currency, from);
  }

  /**
   * @notice disburses fees to a party like collectors and returns the disbursed amount
   */
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
    for (uint256 i = 0; i < numRecipients;) {
      if (feeRecipients[i] != address(0) && feeAmounts[i] != 0) {
        IERC20(currency).safeTransferFrom(from, feeRecipients[i], feeAmounts[i]);
        partyFees += feeAmounts[i];

        emit FeeDistributed(partyName, collection, tokenId, feeRecipients[i], currency, feeAmounts[i]);
      }
      unchecked {
        ++i;
      }
    }
    return partyFees;
  }

  /**
   * @notice Calculate protocol fee for an execution complication
   * @param execComplication complication
   * @param amount amount to transfer
   */
  function _calculateProtocolFee(address execComplication, uint256 amount) internal view returns (uint256) {
    uint256 protocolFee = IComplication(execComplication).getProtocolFee();
    return (protocolFee * amount) / 10000;
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

  // ================================================= Admin functions ==================================================

  /**
   * @notice Updates safu fees
   * @param safuFeeBps new safu fees
   */
  function updateSafuFees(uint256 safuFeeBps) external onlyOwner {
    SAFU_FEE_BPS = safuFeeBps;
    emit SafuFeeUpdated(safuFeeBps);
  }

  /**
   * @notice Updates safu fee recipient
   * @param _safuFeeRecipient new recipient for protocol fees
   */
  function updateSafuFeeRecipient(address _safuFeeRecipient) external onlyOwner {
    SAFU_FEE_RECIPIENT = _safuFeeRecipient;
    emit NewProtocolFeeRecipient(_safuFeeRecipient);
  }

  /**
   * @notice Updates protocol fee recipient
   * @param _protocolFeeRecipient new recipient for protocol fees
   */
  function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
    PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
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
   * @notice Removes a FeeManager
   * @param managerAddress managerAddress address of the manager to remove
   */
  function removeFeeManager(address managerAddress) external onlyOwner {
    require(_feeManagers.contains(managerAddress), 'FeeManager: Not found');
    _feeManagers.remove(managerAddress);

    emit FeeManagerRemoved(managerAddress);
  }
}
