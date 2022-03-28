// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20, SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/IMerkleDistributor.sol';

contract MerkleDistributor is Ownable, IMerkleDistributor {
  using SafeERC20 for IERC20;

  address public immutable override token;
  bytes32 public override merkleRoot;
  mapping(address => uint256) public cumulativeClaimed;

  constructor(address _token) {
    token = _token;
  }

  // =================================================== USER FUNCTIONS =======================================================
  function claim(
    address account,
    uint256 cumulativeAmount,
    bytes32 expectedMerkleRoot,
    bytes32[] calldata merkleProof
  ) external override {
    require(merkleRoot == expectedMerkleRoot, 'Merkle distributor: Merkle root was updated');

    // Verify the merkle proof
    bytes32 leaf = keccak256(abi.encodePacked(account, cumulativeAmount));
    require(_verifyAsm(merkleProof, expectedMerkleRoot, leaf), 'Merkle distributor: Invalid proof');

    // Mark it claimed
    uint256 preclaimed = cumulativeClaimed[account];
    require(preclaimed < cumulativeAmount, 'Merkle distributor: Nothing to claim');
    cumulativeClaimed[account] = cumulativeAmount;

    // Send the token
    unchecked {
      uint256 amount = cumulativeAmount - preclaimed;
      IERC20(token).safeTransfer(account, amount);
      emit Claimed(account, amount);
    }
  }

  function verify(
    bytes32[] calldata proof,
    bytes32 root,
    bytes32 leaf
  ) external pure override returns (bool) {
    return _verifyAsm(proof, root, leaf);
  }

  // =================================================== INTERNAL FUNCTIONS =======================================================

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

  // =================================================== ADMIN FUNCTIONS =======================================================
  function setMerkleRoot(bytes32 _merkleRoot) external override onlyOwner {
    emit MerkelRootUpdated(merkleRoot, _merkleRoot);
    merkleRoot = _merkleRoot;
  }
}
