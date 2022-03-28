// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ERC20Burnable} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import {ERC20Snapshot} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol';
import {TimelockConfig} from './TimelockConfig.sol';

contract InfinityToken is ERC20('Infinity', 'NFT'), ERC20Burnable, ERC20Snapshot, TimelockConfig {
  bytes32 public constant INFLATION_CONFIG_ID = keccak256('Inflation');
  bytes32 public constant EPOCH_DURATION_CONFIG_ID = keccak256('EpochDuration');
  bytes32 public constant CLIFF_CONFIG_ID = keccak256('Cliff');
  bytes32 public constant TOTAL_EPOCHS_CONFIG_ID = keccak256('TotalEpochs');

  /* storage */
  uint256 private _startingEpoch;
  uint256 private _epoch;
  uint256 private _previousEpochTimestamp;

  /* events */
  event Advanced(uint256 epoch, uint256 supplyMinted);

  /* constructor */

  constructor(
    address admin,
    uint256 inflation,
    uint256 epochDuration,
    uint256 cliff,
    uint256 totalEpochs,
    uint256 timelock,
    uint256 supply,
    uint256 epochStart
  ) TimelockConfig(admin, timelock) {
    // set config
    TimelockConfig._setRawConfig(INFLATION_CONFIG_ID, inflation);
    TimelockConfig._setRawConfig(EPOCH_DURATION_CONFIG_ID, epochDuration);
    TimelockConfig._setRawConfig(CLIFF_CONFIG_ID, cliff);
    TimelockConfig._setRawConfig(TOTAL_EPOCHS_CONFIG_ID, totalEpochs);

    // set epoch timestamp
    _previousEpochTimestamp = epochStart; // TODO: should this not be block.timestamp?
    _startingEpoch = epochStart; // TODO: should this not be block.timestamp?

    // mint initial supply
    ERC20._mint(admin, supply);
  }

  /* user functions */

  function advance() external {
    require(_epoch < getTotalEpochs(), 'no epochs left');

    require(block.timestamp >= _startingEpoch + getCliff(), 'cliff not passed');

    require(block.timestamp >= _previousEpochTimestamp + getEpochDuration(), 'not ready to advance');

    uint256 epochsPassed = (block.timestamp - _previousEpochTimestamp) / getEpochDuration();
    uint256 epochsLeft = getTotalEpochs() - _epoch;
    epochsPassed = epochsPassed > epochsLeft ? epochsLeft : epochsPassed;

    // set epoch
    _epoch += epochsPassed;
    _previousEpochTimestamp = block.timestamp;

    // create snapshot
    ERC20Snapshot._snapshot(); // TODO: should snapshot not be taken after mint to include the newly issued tokens?

    // calculate inflation amount
    uint256 supplyMinted = getInflation() * epochsPassed;

    // mint to treasurer
    ERC20._mint(getAdmin(), supplyMinted);

    // emit event
    emit Advanced(_epoch, supplyMinted);
  }

  /* hook functions */

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20, ERC20Snapshot) {
    ERC20Snapshot._beforeTokenTransfer(from, to, amount);
  }

  /* view functions */
  function getEpoch() public view returns (uint256 epoch) {
    return _epoch;
  }

  function getAdmin() public view returns (address admin) {
    return address(uint160(TimelockConfig.getConfig(TimelockConfig.ADMIN_CONFIG_ID).value));
  }

  function getTimelock() public view returns (uint256 timelock) {
    return TimelockConfig.getConfig(TimelockConfig.TIMELOCK_CONFIG_ID).value;
  }

  function getInflation() public view returns (uint256 inflation) {
    return TimelockConfig.getConfig(INFLATION_CONFIG_ID).value;
  }

  function getCliff() public view returns (uint256 cliff) {
    return TimelockConfig.getConfig(CLIFF_CONFIG_ID).value;
  }

  function getTotalEpochs() public view returns (uint256 totalEpochs) {
    return TimelockConfig.getConfig(TOTAL_EPOCHS_CONFIG_ID).value;
  }

  function getEpochDuration() public view returns (uint256 epochDuration) {
    return TimelockConfig.getConfig(EPOCH_DURATION_CONFIG_ID).value;
  }
}
