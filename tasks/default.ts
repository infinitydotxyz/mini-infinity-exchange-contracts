import { formatEther } from 'ethers/lib/utils';
import { task } from 'hardhat/config';
import { deployContract } from './utils';

const WETH_ADDRESS = undefined; // todo: change this to the address of WETH contract;

task('deployAll', 'Deploy all contracts')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const mock20 = await run('deployMock20', { verify: args.verify });

    const mock721 = await run('deployMock721', { verify: args.verify });

    const currencyRegistry = await run('deployCurrencyRegistry', { verify: args.verify });

    const complicationRegistry = await run('deployComplicationRegistry', { verify: args.verify });

    const infinityExchange = await run('deployExchange', {
      verify: args.verify,
      currencyregistry: currencyRegistry.address,
      complicationregistry: complicationRegistry.address,
      wethaddress: WETH_ADDRESS ?? mock20.address
    });
  });

task('deployMock20', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const mock20 = await deployContract('MockERC20', await ethers.getContractFactory('MockERC20'), signer);

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await mock20.deployTransaction.wait(5);
      await run('verify:verify', {
        address: mock20.address,
        contract: 'contracts/MockERC20.sol:MockERC20'
      });
    }
    return mock20;
  });

task('deployMock721', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const mock721 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer);

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await mock721.deployTransaction.wait(5);
      await run('verify:verify', {
        address: mock721.address,
        contract: 'contracts/MockERC721.sol:MockERC721'
      });
    }
    return mock721;
  });

task('deployCurrencyRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const currencyRegistry = await deployContract(
      'CurrencyRegistry',
      await ethers.getContractFactory('CurrencyRegistry'),
      signer
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await currencyRegistry.deployTransaction.wait(5);
      await run('verify:verify', {
        address: currencyRegistry.address,
        contract: 'contracts/core/CurrencyRegistry.sol:CurrencyRegistry'
      });
    }
    return currencyRegistry;
  });

task('deployComplicationRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const complicationRegistry = await deployContract(
      'ComplicationRegistry',
      await ethers.getContractFactory('ComplicationRegistry'),
      signer
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await complicationRegistry.deployTransaction.wait(5);
      await run('verify:verify', {
        address: complicationRegistry.address,
        contract: 'contracts/core/ComplicationRegistry.sol:ComplicationRegistry'
      });
    }
    return complicationRegistry;
  });

task('deployExchange', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('currencyregistry', 'currency registry address')
  .addParam('complicationregistry', 'complication registry address')
  .addParam('wethaddress', 'weth address')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const infinityExchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange'),
      signer,
      [args.currencyregistry, args.complicationregistry, args.wethaddress]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityExchange.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityExchange.address,
        contract: 'contracts/core/InfinityExchange.sol:InfinityExchange',
        constructorArguments: [args.currencyregistry, args.complicationregistry, args.wethaddress]
      });
    }
    return infinityExchange;
  });
