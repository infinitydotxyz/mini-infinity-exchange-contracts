import { task } from 'hardhat/config';
import { deployContract } from './utils';
import { BigNumber, Contract } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
require('dotenv').config();

// mainnet
// const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
// polygon
const WETH_ADDRESS = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619';

// other vars
let infinityExchange: Contract,
  infinityOBComplication: Contract,
  infinityCreatorsFeeRegistry: Contract,
  infinityCreatorsFeeManager: Contract;

function toBN(val: string | number) {
  return BigNumber.from(val.toString());
}

task('deployAll', 'Deploy all contracts')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const signer2 = (await ethers.getSigners())[1];

    infinityCreatorsFeeRegistry = await run('deployInfinityCreatorsFeeRegistry', {
      verify: args.verify
    });

    infinityCreatorsFeeManager = await run('deployInfinityCreatorsFeeManager', {
      verify: args.verify,
      creatorsfeeregistry: infinityCreatorsFeeRegistry.address
    });

    infinityExchange = await run('deployInfinityExchange', {
      verify: args.verify,
      wethaddress: WETH_ADDRESS,
      matchexecutor: signer2.address,
      creatorsfeemanager: infinityCreatorsFeeManager.address
    });

    infinityOBComplication = await run('deployInfinityOrderBookComplication', {
      verify: args.verify,
      protocolfee: '250',
      errorbound: parseEther('0.01').toString()
    });

    // run post deploy actions
    await run('postDeployActions');
  });

task('deployInfinityCreatorsFeeRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const signer1 = (await ethers.getSigners())[0];
    const creatorsFeeRegistry = await deployContract(
      'InfinityCreatorsFeeRegistry',
      await ethers.getContractFactory('InfinityCreatorsFeeRegistry'),
      signer1
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await creatorsFeeRegistry.deployTransaction.wait(5);
      await run('verify:verify', {
        address: creatorsFeeRegistry.address,
        contract: 'contracts/core/InfinityCreatorsFeeRegistry.sol:InfinityCreatorsFeeRegistry'
      });
    }
    return creatorsFeeRegistry;
  });

task('deployInfinityCreatorsFeeManager', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('creatorsfeeregistry', 'creators fee registry address')
  .setAction(async (args, { ethers, run, network }) => {
    const signer1 = (await ethers.getSigners())[0];
    const infinityCreatorsFeeManager = await deployContract(
      'InfinityCreatorsFeeManager',
      await ethers.getContractFactory('InfinityCreatorsFeeManager'),
      signer1,
      [args.creatorsfeeregistry]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityCreatorsFeeManager.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityCreatorsFeeManager.address,
        contract: 'contracts/core/InfinityCreatorsFeeManager.sol:InfinityCreatorsFeeManager',
        constructorArguments: [args.creatorsfeeregistry]
      });
    }
    return infinityCreatorsFeeManager;
  });

task('deployInfinityExchange', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('wethaddress', 'weth address')
  .addParam('matchexecutor', 'matchexecutor address')
  .addParam('creatorsfeemanager', 'creators fee manager address')
  .setAction(async (args, { ethers, run, network }) => {
    const signer1 = (await ethers.getSigners())[0];
    const infinityExchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange'),
      signer1,
      [args.wethaddress, args.matchexecutor, args.creatorsfeemanager]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityExchange.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityExchange.address,
        contract: 'contracts/core/InfinityExchange.sol:InfinityExchange',
        constructorArguments: [args.wethaddress, args.matchexecutor, args.creatorsfeemanager]
      });
    }
    return infinityExchange;
  });

task('deployInfinityOrderBookComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .setAction(async (args, { ethers, run, network }) => {
    const signer1 = (await ethers.getSigners())[0];
    const obComplication = await deployContract(
      'InfinityOrderBookComplication',
      await ethers.getContractFactory('InfinityOrderBookComplication'),
      signer1,
      [args.protocolfee, args.errorbound]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await obComplication.deployTransaction.wait(5);
      await run('verify:verify', {
        address: obComplication.address,
        contract: 'contracts/core/InfinityOrderBookComplication.sol:InfinityOrderBookComplication',
        constructorArguments: [args.protocolfee, args.errorbound]
      });
    }
    return obComplication;
  });

task('postDeployActions', 'Post deploy').setAction(async (args, { ethers, run, network }) => {
  console.log('Post deploy actions');

  // add currencies to registry
  console.log('Adding currency');
  await infinityExchange.addCurrency(WETH_ADDRESS);

  // add complications to registry
  console.log('Adding complication to registry');
  await infinityExchange.addComplication(infinityOBComplication.address);

  // set creator fee manager on registry
  console.log('Updating creators fee manager on creators fee registry');
  await infinityCreatorsFeeRegistry.updateCreatorsFeeManager(infinityCreatorsFeeManager.address);
});
