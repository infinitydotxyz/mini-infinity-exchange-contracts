import { task } from 'hardhat/config';

task('verifySig', 'Verify order signature')
  .setAction(async (args, { ethers, run, network }) => {
    const { hash, r, s, v } = args;
    const signer = (await ethers.getSigners())[0];
    const recoveredAddress = ethers.utils.recoverAddress(hash, { r, s, v });
    console.log('Recovered address:', recoveredAddress);
    console.log('Signer address:', signer.address);
    if (recoveredAddress !== signer.address) {
      throw new Error('Signature verification failed');
    }
  });
