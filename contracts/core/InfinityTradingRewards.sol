// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IStaker, StakeLevel} from '../interfaces/IStaker.sol';
import {IMerkleDistributor} from '../interfaces/IMerkleDistributor.sol';

/**
 * @title InfinityTradingRewards
 * @notice allocates and distribvutes trading rewards
 */
contract InfinityTradingRewards is IMerkleDistributor, Ownable {
  using SafeERC20 for IERC20;

  event RewardClaimed(address indexed user, address currency, uint256 amount);

  // currency address to root
  mapping(address => bytes32) public merkleRoots;
  // user to currency to claimed amount
  mapping(address => mapping(address => uint256)) public cumulativeClaimed;

  function claimRewards(
    address currency,
    uint256 cumulativeAmount,
    bytes32 expectedMerkleRoot,
    bytes32[] calldata merkleProof
  ) external {
    // process
    _processClaim(currency, cumulativeAmount, expectedMerkleRoot, merkleProof);

    // transfer
    unchecked {
      uint256 amount = cumulativeAmount - cumulativeClaimed[msg.sender][currency];
      IERC20(currency).safeTransfer(msg.sender, amount);
      emit RewardClaimed(msg.sender, currency, amount);
    }
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

  // ================================================= ADMIN FUNCTIONS ==================================================

  function setMerkleRoot(address currency, bytes32 _merkleRoot) external override onlyOwner {
    emit MerkelRootUpdated(currency, merkleRoots[currency], _merkleRoot);
    merkleRoots[currency] = _merkleRoot;
  }

  function rescueTokens(
    address destination,
    address currency,
    uint256 amount
  ) external onlyOwner {
    IERC20(currency).safeTransfer(destination, amount);
  }
}
