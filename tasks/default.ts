import { formatEther } from 'ethers/lib/utils';
import { task } from 'hardhat/config';
import { deployContract } from './utils';

task('deployMock20', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract('MockERC20', await ethers.getContractFactory('MockERC20'), signer);

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/MockERC20.sol:MockERC20'
      });
    }
  });

task('deployMock721', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer);

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/MockERC721.sol:MockERC721'
      });
    }
  });

task('deployRegistry', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract(
      'WyvernProxyRegistry',
      await ethers.getContractFactory('WyvernProxyRegistry'),
      signer
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/WyvernProxyRegistry.sol:WyvernProxyRegistry'
      });
    }
  });

task('deployTokenTransferProxy', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('proxy', 'Proxy registry address')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract(
      'WyvernTokenTransferProxy',
      await ethers.getContractFactory('WyvernTokenTransferProxy'),
      signer,
      [args.proxy]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/WyvernTokenTransferProxy.sol:WyvernTokenTransferProxy',
        constructorArguments: [args.proxy]
      });
    }
  });

task('deployExchange', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('proxy', 'Proxy registry address')
  .addParam('tokentransferproxy', 'tokenTransferProxyAddress')
  .addParam('tokenaddress', 'tokenAddress')
  .addParam('protocolfeeaddress', 'protocolFeeAddress')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract(
      'WyvernExchange',
      await ethers.getContractFactory('WyvernExchange'),
      signer,
      [args.proxy, args.tokentransferproxy, args.tokenaddress, args.protocolfeeaddress]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/WyvernExchange.sol:WyvernExchange',
        constructorArguments: [args.proxy, args.tokentransferproxy, args.tokenaddress, args.protocolfeeaddress]
      });
    }
  });

task('deployRoyaltyWrapper', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('exchange', 'exchange address')
  .addParam('royaltyengine', 'royalty engine address')
  .addParam('wallet', 'wallet address')
  .setAction(async (args, { ethers, run, network }) => {
    // log config
    console.log('Network');
    console.log('  ', network.name);
    console.log('Task Args');
    console.log(args);

    // compile
    await run('compile');
    // get signer
    const signer = (await ethers.getSigners())[0];
    console.log('Signer');
    console.log('  at', signer.address);
    console.log('  ETH', formatEther(await signer.getBalance()));

    const infinityFactory = await deployContract(
      'WrapperWyvernExchange',
      await ethers.getContractFactory('WrapperWyvernExchange'),
      signer,
      [args.exchange, args.royaltyengine, args.wallet]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityFactory.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityFactory.address,
        contract: 'contracts/WrapperWyvernExchange.sol:WrapperWyvernExchange',
        constructorArguments: [args.exchange, args.royaltyengine, args.wallet]
      });
    }
  });
