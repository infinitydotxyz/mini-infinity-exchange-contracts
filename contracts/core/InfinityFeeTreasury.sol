// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IInfinityFeeTreasury} from '../interfaces/IInfinityFeeTreasury.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IComplication} from '../interfaces/IComplication.sol';
import {IStaker, StakeLevel} from '../interfaces/IStaker.sol';
import {IFeeManager, FeeParty} from '../interfaces/IFeeManager.sol';
import {IMerkleDistributor} from '../interfaces/IMerkleDistributor.sol';

/**
 * @title InfinityFeeTreasury
 * @notice allocates and disburses fees to all parties: protocol/safu fund/creators/curators/collectors
 */
contract InfinityFeeTreasury is IInfinityFeeTreasury, IMerkleDistributor, Ownable {
  using SafeERC20 for IERC20;

  address public INFINITY_EXCHANGE;
  address public STAKER_CONTRACT;
  address public CREATOR_FEE_MANAGER;
  address public COLLECTOR_FEE_MANAGER;

  uint16 public PROTOCOL_FEE_BPS = 50;
  uint16 public SAFU_FEE_BPS = 50;
  uint16 public CURATOR_FEE_BPS = 75;

  uint16 BRONZE_FEE_DISCOUNT_BPS = 1000;
  uint16 SILVER_FEE_DISCOUNT_BPS = 2000;
  uint16 GOLD_FEE_DISCOUNT_BPS = 3000;
  uint16 PLATINUM_FEE_DISCOUNT_BPS = 4000;

  event ProtocolFeesClaimed(address destination, address currency, uint256 amount);
  event SafuFeesClaimed(address destination, address currency, uint256 amount);
  event CreatorFeesClaimed(address indexed user, address currency, uint256 amount);
  event CuratorFeesClaimed(address indexed user, address currency, uint256 amount);
  event CollectorFeesClaimed(address indexed collection, address currency, uint256 amount);

  event StakerContractUpdated(address stakingContract);
  event CreatorFeeManagerUpdated(address manager);
  event CollectorFeeManagerUpdated(address manager);

  event ProtocolFeeUpdated(uint16 newBps);
  event SafuFeeUpdated(uint16 newBps);
  event CuratorFeeUpdated(uint16 newBps);
  event FeeDiscountUpdated(StakeLevel level, uint16 newBps);

  event FeeDistributed(
    FeeParty partyName,
    address indexed collection,
    uint256 indexed tokenId,
    address indexed recipient,
    address currency,
    uint256 amount
  );

  // currency address to amounts
  mapping(address => uint256) public protocolFees;
  mapping(address => uint256) public safuFees;
  // creator address to currency to amount
  mapping(address => mapping(address => uint256)) public creatorFees;
  // currency to amount
  mapping(address => uint256) public curatorFees;
  // collection fee share treasury contract address to currency to amount
  mapping(address => mapping(address => uint256)) public collectorFees;
  // currency address to root
  mapping(address => bytes32) public merkleRoots;
  // user to currency to claimed amount
  mapping(address => mapping(address => uint256)) public cumulativeClaimed;

  constructor(
    address _infinityExchange,
    address _stakerContract,
    address _creatorFeeManager,
    address _collectorFeeManager
  ) {
    INFINITY_EXCHANGE = _infinityExchange;
    STAKER_CONTRACT = _stakerContract;
    CREATOR_FEE_MANAGER = _creatorFeeManager;
    COLLECTOR_FEE_MANAGER = _collectorFeeManager;
  }

  function allocateFees(
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
    // token staker discount
    uint16 feeDiscountBps = _getFeeDiscountBps(seller);

    // protocol and safu fund fee
    uint256 totalFees = _allocateFeesToProtocolAndSafuFund(execComplication, amount, currency, feeDiscountBps);

    // creator fee
    totalFees += _allocateFeesToCreators(execComplication, collection, tokenId, amount, currency);

    // curator fee
    totalFees += _allocateFeesToCurators(collection, tokenId, amount, currency, feeDiscountBps);

    // collector fee
    totalFees += _allocateFeesToCollectors(execComplication, collection, tokenId, amount, currency, feeDiscountBps);

    // transfer fees to contract
    IERC20(currency).safeTransferFrom(buyer, address(this), totalFees);

    // check min bps to seller is met
    uint256 remainingAmount = amount - totalFees;
    require((remainingAmount * 10000) >= (minBpsToSeller * amount), 'Fees: Higher than expected');
    // transfer final amount (post-fees) to seller
    IERC20(currency).safeTransferFrom(buyer, seller, remainingAmount);
  }

  function claimCreatorFees(address currency) external {
    require(creatorFees[msg.sender][currency] > 0, 'Fees: No creator fees to claim');
    creatorFees[msg.sender][currency] = 0;
    IERC20(currency).safeTransfer(msg.sender, creatorFees[msg.sender][currency]);
    emit CreatorFeesClaimed(msg.sender, currency, creatorFees[msg.sender][currency]);
  }

  function claimCuratorFees(
    address currency,
    uint256 cumulativeAmount,
    bytes32 expectedMerkleRoot,
    bytes32[] calldata merkleProof
  ) external override {
    // process
    _processClaim(currency, cumulativeAmount, expectedMerkleRoot, merkleProof);

    // transfer
    unchecked {
      uint256 amount = cumulativeAmount - cumulativeClaimed[msg.sender][currency];
      curatorFees[currency] -= amount;
      IERC20(currency).safeTransfer(msg.sender, amount);
      emit CuratorFeesClaimed(msg.sender, currency, amount);
    }
  }

  function claimCollectorFees(address currency) external {
    require(collectorFees[msg.sender][currency] > 0, 'Fees: No collector fees to claim');
    collectorFees[msg.sender][currency] = 0;
    IERC20(currency).safeTransfer(msg.sender, collectorFees[msg.sender][currency]);
    emit CollectorFeesClaimed(msg.sender, currency, collectorFees[msg.sender][currency]);
  }

  function verify(
    bytes32[] calldata proof,
    bytes32 root,
    bytes32 leaf
  ) external pure override returns (bool) {
    return _verifyAsm(proof, root, leaf);
  }

  // ====================================================== INTERNAL FUNCTIONS ================================================

  function _processClaim(
    address currency,
    uint256 cumulativeAmount,
    bytes32 expectedMerkleRoot,
    bytes32[] calldata merkleProof
  ) internal {
    require(merkleRoots[currency] == expectedMerkleRoot, 'invalid merkle root');

    // Verify the merkle proof
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender, cumulativeAmount));
    require(_verifyAsm(merkleProof, expectedMerkleRoot, leaf), 'invalid merkle proof');

    // Mark it claimed
    uint256 preclaimed = cumulativeClaimed[msg.sender][currency];
    require(preclaimed < cumulativeAmount, 'merkle: nothing to claim');
    cumulativeClaimed[msg.sender][currency] = cumulativeAmount;
  }

  function _getFeeDiscountBps(address user) internal view returns (uint16) {
    StakeLevel stakeLevel = IStaker(STAKER_CONTRACT).getUserStakeLevel(user);
    if (stakeLevel == StakeLevel.BRONZE) {
      return BRONZE_FEE_DISCOUNT_BPS;
    } else if (stakeLevel == StakeLevel.SILVER) {
      return SILVER_FEE_DISCOUNT_BPS;
    } else if (stakeLevel == StakeLevel.GOLD) {
      return GOLD_FEE_DISCOUNT_BPS;
    } else if (stakeLevel == StakeLevel.PLATINUM) {
      return PLATINUM_FEE_DISCOUNT_BPS;
    }
    return 0;
  }

  /**
   * @notice allocates protocol and safu fund fees and returns the disbursed amount
   */
  function _allocateFeesToProtocolAndSafuFund(
    address execComplication,
    uint256 amount,
    address currency,
    uint16 feeDiscountBps
  ) internal returns (uint256) {
    uint256 protocolFeeAmount = (_calculateProtocolFee(execComplication, amount) * feeDiscountBps) / 10000;
    uint256 safuFeeAmount = (((SAFU_FEE_BPS * amount) / 10000) * feeDiscountBps) / 10000;
    // update storage
    protocolFees[currency] += protocolFeeAmount;
    safuFees[currency] += safuFeeAmount;
    return protocolFeeAmount + safuFeeAmount;
  }

  function _allocateFeesToCreators(
    address execComplication,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency
  ) internal returns (uint256) {
    IFeeManager feeManager = IFeeManager(CREATOR_FEE_MANAGER);
    (FeeParty partyName, address[] memory feeRecipients, uint256[] memory feeAmounts) = feeManager
      .calcFeesAndGetRecipients(execComplication, collection, tokenId, amount);

    uint256 partyFees = 0;
    for (uint256 i = 0; i < feeRecipients.length; ) {
      if (feeRecipients[i] != address(0) && feeAmounts[i] != 0) {
        creatorFees[feeRecipients[i]][currency] += feeAmounts[i];
        partyFees += feeAmounts[i];
        emit FeeDistributed(partyName, collection, tokenId, feeRecipients[i], currency, feeAmounts[i]);
      }
      unchecked {
        ++i;
      }
    }
    return partyFees;
  }

  function _allocateFeesToCurators(
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    uint16 feeDiscountBps
  ) internal returns (uint256) {
    uint256 curatorFee = (((CURATOR_FEE_BPS * amount) / 10000) * feeDiscountBps) / 10000;
    // update storage
    curatorFees[currency] += curatorFee;
    emit FeeDistributed(FeeParty.CURATORS, collection, tokenId, address(this), currency, curatorFee);
    return curatorFee;
  }

  function _allocateFeesToCollectors(
    address execComplication,
    address collection,
    uint256 tokenId,
    uint256 amount,
    address currency,
    uint16 feeDiscountBps
  ) internal returns (uint256) {
    IFeeManager feeManager = IFeeManager(COLLECTOR_FEE_MANAGER);
    (FeeParty partyName, address[] memory feeRecipients, uint256[] memory feeAmounts) = feeManager
      .calcFeesAndGetRecipients(execComplication, collection, tokenId, amount);

    uint256 partyFees = 0;
    for (uint256 i = 0; i < feeRecipients.length; ) {
      uint256 feeAmount = (feeAmounts[i] * feeDiscountBps) / 10000;
      if (feeRecipients[i] != address(0) && feeAmount != 0) {
        collectorFees[feeRecipients[i]][currency] += feeAmount;
        partyFees += feeAmount;
        emit FeeDistributed(partyName, collection, tokenId, feeRecipients[i], currency, feeAmount);
      } else if (feeRecipients[i] == address(0) && feeAmount != 0) {
        // if collection is not setup, send coll fees to protocol
        protocolFees[currency] += feeAmount;
        partyFees += feeAmount;
        emit FeeDistributed(FeeParty.PROTOCOL, collection, tokenId, feeRecipients[i], currency, feeAmount);
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

  function _verifyAsm(
    bytes32[] calldata proof,
    bytes32 root,
    bytes32 leaf
  ) private pure returns (bool valid) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      let mem1 := mload(0x40)
      let mem2 := add(mem1, 0x20)
      let ptr := proof.offset

      for {
        let end := add(ptr, mul(0x20, proof.length))
      } lt(ptr, end) {
        ptr := add(ptr, 0x20)
      } {
        let node := calldataload(ptr)

        switch lt(leaf, node)
        case 1 {
          mstore(mem1, leaf)
          mstore(mem2, node)
        }
        default {
          mstore(mem1, node)
          mstore(mem2, leaf)
        }

        leaf := keccak256(mem1, 0x40)
      }

      valid := eq(root, leaf)
    }
  }

  // ====================================================== VIEW FUNCTIONS ================================================

  function getFeeDiscountBps(address user) external view returns (uint16) {
    return _getFeeDiscountBps(user);
  }

  // ================================================= ADMIN FUNCTIONS ==================================================

  function claimProtocolFees(address currency, address destination) external onlyOwner {
    require(protocolFees[currency] > 0, 'Fees: No protocol fees to claim');
    protocolFees[currency] = 0;
    IERC20(currency).safeTransfer(destination, protocolFees[currency]);
    emit ProtocolFeesClaimed(destination, currency, protocolFees[currency]);
  }

  function claimSafuFees(address currency, address destination) external onlyOwner {
    require(safuFees[currency] > 0, 'Fees: No safu fees to claim');
    safuFees[currency] = 0;
    IERC20(currency).safeTransfer(destination, safuFees[currency]);
    emit SafuFeesClaimed(destination, currency, safuFees[currency]);
  }

  function updateStakingContractAddress(address _stakerContract) external onlyOwner {
    STAKER_CONTRACT = _stakerContract;
    emit StakerContractUpdated(_stakerContract);
  }

  function updateCreatorFeeManager(address manager) external onlyOwner {
    CREATOR_FEE_MANAGER = manager;
    emit CreatorFeeManagerUpdated(manager);
  }

  function updateCollectorFeeManager(address manager) external onlyOwner {
    COLLECTOR_FEE_MANAGER = manager;
    emit CollectorFeeManagerUpdated(manager);
  }

  function updateProtocolFees(uint16 bps) external onlyOwner {
    PROTOCOL_FEE_BPS = bps;
    emit ProtocolFeeUpdated(bps);
  }

  function updateSafuFees(uint16 bps) external onlyOwner {
    SAFU_FEE_BPS = bps;
    emit SafuFeeUpdated(bps);
  }

  function updateCuratorFees(uint16 bps) external onlyOwner {
    CURATOR_FEE_BPS = bps;
    emit CuratorFeeUpdated(bps);
  }

  function updateFeeDiscountBps(StakeLevel stakeLevel, uint16 bps) external onlyOwner {
    if (stakeLevel == StakeLevel.BRONZE) {
      BRONZE_FEE_DISCOUNT_BPS = bps;
    } else if (stakeLevel == StakeLevel.SILVER) {
      SILVER_FEE_DISCOUNT_BPS = bps;
    } else if (stakeLevel == StakeLevel.GOLD) {
      GOLD_FEE_DISCOUNT_BPS = bps;
    } else if (stakeLevel == StakeLevel.PLATINUM) {
      PLATINUM_FEE_DISCOUNT_BPS = bps;
    }
    emit FeeDiscountUpdated(stakeLevel, bps);
  }

  function setMerkleRoot(address currency, bytes32 _merkleRoot) external override onlyOwner {
    emit MerkelRootUpdated(currency, merkleRoots[currency], _merkleRoot);
    merkleRoots[currency] = _merkleRoot;
  }
}
