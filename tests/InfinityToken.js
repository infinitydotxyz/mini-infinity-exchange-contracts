import { expect } from 'chai';
import { ethers, network } from 'hardhat';

describe('Infinity Token', function () {
  let signers, token; //leaves, proofs, root

  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
  const MINUTE = 60;
  const HOUR = MINUTE * 60;
  const DAY = HOUR * 24;
  const MONTH = DAY * 30;
  const UNIT = toBN(1e18);
  const INFLATION = toBN(40_000_000).mul(UNIT); // 40m
  const EPOCH_DURATION = MONTH;
  const CLIFF = toBN(6);
  const CLIFF_PERIOD = CLIFF.mul(MONTH);
  const TOTAL_EPOCHS = 25;
  const TIMELOCK = 7 * DAY;
  const INITIAL_SUPPLY = toBN(1_000_000_000).mul(UNIT); // 1b

  function toBN(val) {
    return ethers.BigNumber.from(val.toString());
  }

  before(async () => {
    signers = await ethers.getSigners();
    const InfinityToken = await ethers.getContractFactory('InfinityToken');
    let now = (await signers[0].provider.getBlock('latest')).timestamp;
    token = await InfinityToken.deploy(
      signers[0].address,
      INFLATION.toString(),
      EPOCH_DURATION.toString(),
      CLIFF_PERIOD.toString(),
      TOTAL_EPOCHS.toString(),
      TIMELOCK.toString(),
      INITIAL_SUPPLY.toString()
    );
    await token.deployed();
  });

  // beforeEach(async () => {

  // });

  describe('Setup', () => {
    it('Should init properly', async function () {
      expect(await token.name()).to.equal('Infinity');
      expect(await token.symbol()).to.equal('NFT');
      expect(await token.getAdmin()).to.equal(signers[0].address);
      expect(await token.getTimelock()).to.equal(TIMELOCK);
      expect(await token.getInflation()).to.equal(INFLATION);
      expect(await token.getCliff()).to.equal(CLIFF_PERIOD);
      expect(await token.getTotalEpochs()).to.equal(TOTAL_EPOCHS);
      expect(await token.getEpochDuration()).to.equal(EPOCH_DURATION);
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await token.balanceOf(signers[0].address)).to.equal(INITIAL_SUPPLY);
    });
  });

  describe('Pre-cliff', () => {
    it('Should not allow advancing directly after deployment', async function () {
      await expect(token.advance()).to.be.revertedWith('cliff not passed');
    });
    it('Should not allow advancing even if very close to the cliff', async function () {
      await network.provider.send('evm_increaseTime', [CLIFF_PERIOD.sub(5 * MINUTE)]);
      await expect(token.advance()).to.be.revertedWith('cliff not passed');
    });
  });

  describe('Post-cliff', () => {
    it('Should allow advancing after cliff is passed', async function () {
      await network.provider.send('evm_increaseTime', [5 * MINUTE]);
      await token.advance();
      expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
        INITIAL_SUPPLY.add(INFLATION.mul(CLIFF)).toString()
      );
    });
    it('Should not allow advancing again before epoch period has passed', async function () {
      await network.provider.send('evm_increaseTime', [EPOCH_DURATION - 5 * MINUTE]);
      await expect(token.advance()).to.be.revertedWith('not ready to advance');
    });
    it('Should allow advancing after epoch period has passed', async function () {
      await network.provider.send('evm_increaseTime', [5 * MINUTE]);
      await token.advance();
      expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
        INITIAL_SUPPLY.add(INFLATION.mul(CLIFF)).add(INFLATION).toString()
      );
    });
    it('Should not allow advancing again before epoch period has passed', async function () {
      await network.provider.send('evm_increaseTime', [EPOCH_DURATION - 5 * MINUTE]);
      await expect(token.advance()).to.be.revertedWith('not ready to advance');
    });
    it('Should vest full amount if an epoch is missed', async function () {
      await network.provider.send('evm_increaseTime', [EPOCH_DURATION * 2]);
      await token.advance();
      expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
        INITIAL_SUPPLY.add(INFLATION.mul(CLIFF))
          .add(INFLATION.mul(toBN(3)))
          .toString()
      );
    });
    it('Should vest the full amount after all epochs have passed', async function () {
      for (let i = await token.getEpoch(); i < TOTAL_EPOCHS; i++) {
        await network.provider.send('evm_increaseTime', [EPOCH_DURATION]);
        await token.advance();
        expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
          INITIAL_SUPPLY.add(toBN(i).add(toBN(1)).mul(INFLATION)).toString()
        );
      }
      expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
        INITIAL_SUPPLY.add(toBN(TOTAL_EPOCHS).mul(INFLATION)).toString()
      );
      console.log('final balance:', (await token.balanceOf(signers[0].address)).toString());
    });
    it('Should not allow advancing past epoch limit', async function () {
      await network.provider.send('evm_increaseTime', [EPOCH_DURATION]);
      await expect(token.advance()).to.be.revertedWith('no epochs left');
    });
  });
  describe('Update values', () => {
    it('Should not allow a non-owner to make a proposal', async function () {
      let totalEpochs = await token.TOTAL_EPOCHS_CONFIG_ID();
      await expect(token.connect(signers[1]).requestChange(totalEpochs, 22)).to.be.revertedWith('only admin');
    });
    it('Should allow owner to make a proposal', async function () {
      let totalEpochs = await token.TOTAL_EPOCHS_CONFIG_ID();
      await token.requestChange(totalEpochs, 22);
      expect((await token.getTotalEpochs()).toString()).to.equal('21'); // should keep old epoch for now
    });
    it('Should not allow confirmation before period has passed', async function () {
      await network.provider.send('evm_increaseTime', [TIMELOCK - 5 * MINUTE]);
      let totalEpochs = await token.TOTAL_EPOCHS_CONFIG_ID();
      await expect(token.confirmChange(totalEpochs)).to.be.revertedWith('too early');
    });
    it('Should not enact a proposed change in the contract', async function () {
      await expect(token.advance()).to.be.revertedWith('no epochs left');
    });
    it('Should allow confirmation after period has passed', async function () {
      await network.provider.send('evm_increaseTime', [5 * MINUTE]);
      let totalEpochs = await token.TOTAL_EPOCHS_CONFIG_ID();
      await token.confirmChange(totalEpochs);
      expect((await token.getTotalEpochs()).toString()).to.equal('22');
    });
    it('Should enact the confirmed change in the contract and should only pay out the one period even if multiple epochs have been missed', async function () {
      await network.provider.send('evm_increaseTime', [12 * MONTH]);
      await token.advance();
      expect((await token.balanceOf(signers[0].address)).toString()).to.equal(
        INITIAL_SUPPLY.add(toBN(TOTAL_EPOCHS + 1).mul(INFLATION)).toString()
      );
    });
    it('Should allow owner to cancel a proposal', async function () {
      let totalEpochs = await token.TOTAL_EPOCHS_CONFIG_ID();
      await token.requestChange(totalEpochs, 22);
      expect(await token.isPending(totalEpochs));
      expect((await token.getPendingCount()).toString()).to.equal('1');
      await token.cancelChange(totalEpochs);
      expect(!(await token.isPending(totalEpochs)));
      expect((await token.getPendingCount()).toString()).to.equal('0');
    });
    it('Should allow the owner to be changed', async function () {
      let admin = await token.ADMIN_CONFIG_ID();
      await token.requestChange(admin, signers[1].address);
      expect(await token.getAdmin()).to.equal(signers[0].address);
      await network.provider.send('evm_increaseTime', [TIMELOCK]);
      await token.confirmChange(admin);
      expect(await token.getAdmin()).to.equal(signers[1].address);
    });
  });
});