import { task } from 'hardhat/config';
import { deployContract } from './utils';

const WETH_ADDRESS = undefined; // todo: change this to the address of WETH contract;

task('deployAll', 'Deploy all contracts')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    const utilsLib = await run('deployUtils', { verify: args.verify });

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

    const obComplication = await run('deployOBComplication', {
      verify: args.verify,
      protocolfee: '200',
      errorbound: '1000000000'
    });

    const privateSaleComplication = await run('deployPrivateSaleComplication', {
      verify: args.verify,
      protocolfee: '200',
      errorbound: '1000000000',
      utilslib: utilsLib.address
    });

    const collectionSetComplication = await run('deployCollectionSetComplication', {
      verify: args.verify,
      protocolfee: '200',
      errorbound: '1000000000',
      utilslib: utilsLib.address
    });

    const flexiblePriceComplication = await run('deployFlexiblePriceComplication', {
      verify: args.verify,
      protocolfee: '200',
      errorbound: '1000000000',
      utilslib: utilsLib.address
    });
  });

task('deployUtils', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const utilsLib = await deployContract('Utils', await ethers.getContractFactory('Utils'), signer);

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await utilsLib.deployTransaction.wait(5);
      await run('verify:verify', {
        address: utilsLib.address,
        contract: 'contracts/libs/Utils.sol:Utils'
      });
    }
    return utilsLib;
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

task('deployOBComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const obComplication = await deployContract(
      'OrderBookComplication',
      await ethers.getContractFactory('OrderBookComplication'),
      signer,
      [args.protocolfee, args.errorbound]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await obComplication.deployTransaction.wait(5);
      await run('verify:verify', {
        address: obComplication.address,
        contract: 'contracts/core/OrderBookComplication.sol:OrderBookComplication',
        constructorArguments: [args.protocolfee, args.errorbound]
      });
    }
    return obComplication;
  });

task('deployPrivateSaleComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .addParam('utilslib', 'utils lib address')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const privateSaleComplication = await deployContract(
      'PrivateSaleComplication',
      await ethers.getContractFactory('PrivateSaleComplication', {
        libraries: {
          Utils: args.utilslib
        }
      }),
      signer,
      [args.protocolfee, args.errorbound]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await privateSaleComplication.deployTransaction.wait(5);
      await run('verify:verify', {
        address: privateSaleComplication.address,
        contract: 'contracts/core/PrivateSaleComplication.sol:PrivateSaleComplication',
        constructorArguments: [args.protocolfee, args.errorbound]
      });
    }
    return privateSaleComplication;
  });

task('deployCollectionSetComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .addParam('utilslib', 'utils lib address')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const collectionSetComplication = await deployContract(
      'CollectionSetComplication',
      await ethers.getContractFactory('CollectionSetComplication', {
        libraries: {
          Utils: args.utilslib
        }
      }),
      signer,
      [args.protocolfee, args.errorbound]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await collectionSetComplication.deployTransaction.wait(5);
      await run('verify:verify', {
        address: collectionSetComplication.address,
        contract: 'contracts/core/CollectionSetComplication.sol:CollectionSetComplication',
        constructorArguments: [args.protocolfee, args.errorbound]
      });
    }
    return collectionSetComplication;
  });

task('deployFlexiblePriceComplication', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('protocolfee', 'protocol fee')
  .addParam('errorbound', 'error bound')
  .addParam('utilslib', 'utils lib address')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const flexiblePriceComplication = await deployContract(
      'FlexiblePriceComplication',
      await ethers.getContractFactory('FlexiblePriceComplication', {
        libraries: {
          Utils: args.utilslib
        }
      }),
      signer,
      [args.protocolfee, args.errorbound]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await flexiblePriceComplication.deployTransaction.wait(5);
      await run('verify:verify', {
        address: flexiblePriceComplication.address,
        contract: 'contracts/core/FlexiblePriceComplication.sol:FlexiblePriceComplication',
        constructorArguments: [args.protocolfee, args.errorbound]
      });
    }
    return flexiblePriceComplication;
  });
