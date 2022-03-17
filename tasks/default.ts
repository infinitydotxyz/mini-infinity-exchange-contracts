import { formatEther } from 'ethers/lib/utils';
import { task } from 'hardhat/config';
import { deployContract } from './utils';

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
  });

task('deployExchange', 'Deploy')
  .addFlag('verify', 'verify contracts on etherscan')
  .addParam('proxy', 'Proxy registry address')
  .addParam('tokentransferproxy', 'tokenTransferProxyAddress')
  .addParam('tokenaddress', 'tokenAddress')
  .addParam('protocolfeeaddress', 'protocolFeeAddress')
  .setAction(async (args, { ethers, run, network }) => {
    // get signer
    const signer = (await ethers.getSigners())[0];
    const infinityExchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange'),
      signer,
      [args.proxy, args.tokentransferproxy, args.tokenaddress, args.protocolfeeaddress]
    );

    // verify source
    if (args.verify) {
      console.log('Verifying source on etherscan');
      await infinityExchange.deployTransaction.wait(5);
      await run('verify:verify', {
        address: infinityExchange.address,
        contract: 'contracts/core/InfinityExchange.sol:InfinityExchange',
        constructorArguments: [args.proxy, args.tokentransferproxy, args.tokenaddress, args.protocolfeeaddress]
      });
    }
  });
