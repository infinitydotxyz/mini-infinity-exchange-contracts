import { task } from 'hardhat/config';
import { deployContract } from './utils';
import { expect } from 'chai';
import { BigNumber, Contract } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
require('dotenv').config();

// mainnet
// const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
// polygon
const WETH_ADDRESS = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619';

// mainnet
// const ROYALTY_ENGINE = '0x0385603ab55642cb4dd5de3ae9e306809991804f';
// polygon
const ROYALTY_ENGINE = '0x28edfcf0be7e86b07493466e7631a213bde8eef2';

const MINUTE = 60;
const HOUR = MINUTE * 60;
const DAY = HOUR * 24;
const MONTH = DAY * 30;
const YEAR = MONTH * 12;
const UNIT = toBN(1e18);
const INFLATION = toBN(300_000_000).mul(UNIT);
const EPOCH_DURATION = YEAR;
const CLIFF = toBN(3);
const CLIFF_PERIOD = CLIFF.mul(YEAR);
const MAX_EPOCHS = 6;
const TIMELOCK = 30 * DAY;
const INITIAL_SUPPLY = toBN(1_000_000_000).mul(UNIT);

// other vars
let signer1: SignerWithAddress,
  signer2: SignerWithAddress,
  infinityToken: Contract,
  infinityExchange: Contract,
  infinityCurrencyRegistry: Contract,
  infinityComplicationRegistry: Contract,
  infinityOBComplication: Contract,
  infinityTreasurer: string,
  infinityStaker: Contract,
  infinityTradingRewards: Contract,
  infinityFeeTreasury: Contract,
  infinityCreatorsFeeRegistry: Contract,
  infinityCreatorsFeeManager: Contract;

function toBN(val: string | number) {
  return BigNumber.from(val.toString());
}

task('deployAll', 'Deploy all contracts')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    signer1 = (await ethers.getSigners())[0];
    signer2 = (await ethers.getSigners())[1];

    infinityToken = await run('deployInfinityToken', {
      inflation: INFLATION.toString(),
      epochduration: EPOCH_DURATION.toString(),
      cliff: CLIFF_PERIOD.toString(),
      maxepochs: MAX_EPOCHS.toString(),
      timelock: TIMELOCK.toString(),
      supply: INITIAL_SUPPLY.toString(),
      verify: args.verify
    });

    infinityCurrencyRegistry = await run('deployCurrencyRegistry', { verify: args.verify });

    infinityComplicationRegistry = await run('deployComplicationRegistry', { verify: args.verify });

    infinityExchange = await run('deployExchange', {
      verify: args.verify,
      currencyregistry: infinityCurrencyRegistry.address,
      complicationregistry: infinityComplicationRegistry.address,
      wethaddress: WETH_ADDRESS,
      matchexecutor: signer2.address
    });

    infinityOBComplication = await run('deployOBComplication', {
      verify: args.verify,
      protocolfee: '0',
      errorbound: parseEther('0.01').toString()
    });

    infinityTreasurer = signer1.address;

    infinityStaker = await run('deployInfinityStaker', {
      verify: args.verify,
      token: infinityToken.address,
      treasurer: infinityTreasurer
    });

    infinityTradingRewards = await run('deployInfinityTradingRewards', {
      verify: args.verify,
      exchange: infinityExchange.address,
      staker: infinityStaker.address,
      token: infinityToken.address
    });

    infinityCreatorsFeeRegistry = await run('deployInfinityCreatorsFeeRegistry', {
      verify: args.verify
    });

    infinityCreatorsFeeManager = await run('deployInfinityCreatorsFeeManager', {
      verify: args.verify,
      royaltyengine: ROYALTY_ENGINE,
      creatorsfeeregistry: infinityCreatorsFeeRegistry.address
    });

    infinityFeeTreasury = await run('deployInfinityFeeTreasury', {
      verify: args.verify,
      exchange: infinityExchange.address,
      staker: infinityStaker.address,
      creatorsfeemanager: infinityCreatorsFeeManager.address
    });

    // run post deploy actions
    await run('postDeployActions');
  });

task('deployInfinityToken', 'Deploy Infinity token contract')
  .addParam('inflation', 'per epoch inflation')
  .addParam('epochduration', 'epoch duration in days')
  .addParam('cliff', 'initial cliff in days')
  .addParam('maxepochs', 'max number of epochs')
  .addParam('timelock', 'timelock duration in days')
  .addParam('supply', 'initial supply')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run }) => {
    const tokenArgs = [
      signer1.address,
      args.inflation,
      args.epochduration,
      args.cliff,
      args.maxepochs,
      args.timelock,
      args.supply
    ];

    const infinityToken = await deployContract(
      'InfinityToken',
      await ethers.getContractFactory('InfinityToken'),
      signer1,
      tokenArgs
    );

    // verify etherscan
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityToken.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityToken.address,
        contract: 'contracts/token/InfinityToken.sol:InfinityToken',
        constructorArguments: tokenArgs
      });
    }

    return infinityToken;
  });

task('deployCurrencyRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const currencyRegistry = await deployContract(
      'InfinityCurrencyRegistry',
      await ethers.getContractFactory('InfinityCurrencyRegistry'),
      signer1
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await currencyRegistry.deployTransaction.wait(5);
      await run('verify:verify', {
        address: currencyRegistry.address,
        contract: 'contracts/core/InfinityCurrencyRegistry.sol:InfinityCurrencyRegistry'
      });
    }
    return currencyRegistry;
  });

task('deployComplicationRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const complicationRegistry = await deployContract(
      'InfinityComplicationRegistry',
      await ethers.getContractFactory('InfinityComplicationRegistry'),
      signer1
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await complicationRegistry.deployTransaction.wait(5);
      await run('verify:verify', {
        address: complicationRegistry.address,
        contract: 'contracts/core/InfinityComplicationRegistry.sol:InfinityComplicationRegistry'
      });
    }
    return complicationRegistry;
  });

task('deployExchange', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('currencyregistry', 'currency registry address')
  .addParam('complicationregistry', 'complication registry address')
  .addParam('wethaddress', 'weth address')
  .addParam('matchexecutor', 'matchexecutor address')
  .setAction(async (args, { ethers, run, network }) => {
    const infinityExchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange'),
      signer1,
      [args.currencyregistry, args.complicationregistry, args.wethaddress, args.matchexecutor]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityExchange.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityExchange.address,
        contract: 'contracts/core/InfinityExchange.sol:InfinityExchange',
        constructorArguments: [args.currencyregistry, args.complicationregistry, args.wethaddress, args.matchexecutor]
      });
    }
    return infinityExchange;
  });

task('deployOBComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .setAction(async (args, { ethers, run, network }) => {
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

task('deployInfinityStaker', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('token', 'infinity token address')
  .addParam('treasurer', 'treasurer address')
  .setAction(async (args, { ethers, run, network }) => {
    const staker = await deployContract('InfinityStaker', await ethers.getContractFactory('InfinityStaker'), signer1, [
      args.token,
      args.treasurer
    ]);

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await staker.deployTransaction.wait(5);
      await run('verify:verify', {
        address: staker.address,
        contract: 'contracts/core/InfinityStaker.sol:InfinityStaker',
        constructorArguments: [args.token, args.treasurer]
      });
    }
    return staker;
  });

task('deployInfinityTradingRewards', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('exchange', 'exchange address')
  .addParam('staker', 'staker address')
  .addParam('token', 'token address')
  .setAction(async (args, { ethers, run, network }) => {
    const rewards = await deployContract(
      'InfinityTradingRewards',
      await ethers.getContractFactory('InfinityTradingRewards'),
      signer1,
      [args.exchange, args.staker, args.token]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await rewards.deployTransaction.wait(5);
      await run('verify:verify', {
        address: rewards.address,
        contract: 'contracts/core/InfinityTradingRewards.sol:InfinityTradingRewards',
        constructorArguments: [args.exchange, args.staker, args.token]
      });
    }
    return rewards;
  });

task('deployInfinityCreatorsFeeRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
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
  .addParam('royaltyengine', 'royalty engine address')
  .addParam('creatorsfeeregistry', 'creators fee registry address')
  .setAction(async (args, { ethers, run, network }) => {
    const infinityCreatorsFeeManager = await deployContract(
      'InfinityCreatorsFeeManager',
      await ethers.getContractFactory('InfinityCreatorsFeeManager'),
      signer1,
      [args.royaltyengine, args.creatorsfeeregistry]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityCreatorsFeeManager.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityCreatorsFeeManager.address,
        contract: 'contracts/core/InfinityCreatorsFeeManager.sol:InfinityCreatorsFeeManager',
        constructorArguments: [args.royaltyengine, args.creatorsfeeregistry]
      });
    }
    return infinityCreatorsFeeManager;
  });

task('deployInfinityFeeTreasury', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('exchange', 'exchange address')
  .addParam('staker', 'staker address')
  .addParam('creatorsfeemanager', 'creators fee manager address')
  .setAction(async (args, { ethers, run, network }) => {
    const infinityFeeTreasury = await deployContract(
      'InfinityFeeTreasury',
      await ethers.getContractFactory('InfinityFeeTreasury'),
      signer1,
      [args.exchange, args.staker, args.creatorsfeemanager]
    );

    // verify source
    if (args.verify) {
      // console.log('Verifying source on etherscan');
      await infinityFeeTreasury.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFeeTreasury.address,
        contract: 'contracts/core/InfinityFeeTreasury.sol:InfinityFeeTreasury',
        constructorArguments: [args.exchange, args.staker, args.creatorsfeemanager]
      });
    }
    return infinityFeeTreasury;
  });

task('postDeployActions', 'Post deploy').setAction(async (args, { ethers, run, network }) => {
  // add currencies to registry
  await infinityCurrencyRegistry.addCurrency(WETH_ADDRESS);

  // add complications to registry
  await infinityComplicationRegistry.addComplication(infinityOBComplication.address);

  // set infinity fee treasury on exchange
  await infinityExchange.updateInfinityFeeTreasury(infinityFeeTreasury.address);

  // set infinity rewards on exchange
  await infinityExchange.updateInfinityTradingRewards(infinityTradingRewards.address);

  // set infinity rewards on staker
  await infinityStaker.updateInfinityRewardsContract(infinityTradingRewards.address);

  // set creator fee manager on registry
  await infinityCreatorsFeeRegistry.updateCreatorsFeeManager(infinityCreatorsFeeManager.address);

  // set reward token
  // await infinityTradingRewards.addRewardToken(infinityToken.address);
  // let rewardTokenFundAmount = INITIAL_SUPPLY.div(4);
  // // @ts-ignore
  // await approveERC20(
  //   signer1.address,
  //   infinityToken.address,
  //   rewardTokenFundAmount,
  //   signer1,
  //   infinityTradingRewards.address
  // );
  // await infinityTradingRewards.fundWithRewardToken(infinityToken.address, signer1.address, rewardTokenFundAmount);

  // send assets
  await infinityToken.transfer(signer2.address, INITIAL_SUPPLY.div(2).toString());
});
