const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const { deployContract } = require('../tasks/utils');

describe('Exchange', function () {
  let signers,
    signer,
    signer2,
    token,
    utils,
    exchange,
    mock721Contract1,
    mock721Contract2,
    mock721Contract3,
    currencyRegistry,
    complicationRegistry,
    obComplication,
    privateSaleComplication,
    infinityTreasury,
    infinityStaker,
    infinityTradingRewards,
    infinityFeeTreasury,
    infinityCreatorsFeeRegistry,
    mockRoyaltyEngine,
    infinityCreatorsFeeManager,
    infinityCollectorsFeeRegistry,
    infinityCollectorsFeeManager;

  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
  const MINUTE = 60;
  const HOUR = MINUTE * 60;
  const DAY = HOUR * 24;
  const MONTH = DAY * 30;
  const YEAR = MONTH * 12;
  const UNIT = toBN(1e18);
  const INFLATION = toBN(300_000_000).mul(UNIT); // 40m
  const EPOCH_DURATION = YEAR;
  const CLIFF = toBN(3);
  const CLIFF_PERIOD = CLIFF.mul(YEAR);
  const MAX_EPOCHS = 6;
  const TIMELOCK = 30 * DAY;
  const INITIAL_SUPPLY = toBN(1_000_000_000).mul(UNIT); // 1b

  function toBN(val) {
    return ethers.BigNumber.from(val.toString());
  }

  before(async () => {
    // signers
    signers = await ethers.getSigners();
    signer = signers[0];
    signer2 = signers[1];

    // token
    const tokenArgs = [
      signer.address,
      INFLATION.toString(),
      EPOCH_DURATION.toString(),
      CLIFF_PERIOD.toString(),
      MAX_EPOCHS.toString(),
      TIMELOCK.toString(),
      INITIAL_SUPPLY.toString()
    ];
    token = await deployContract(
      'InfinityToken',
      await ethers.getContractFactory('InfinityToken'),
      signers[0],
      tokenArgs
    );

    // utils
    utils = await deployContract('Utils', await ethers.getContractFactory('Utils'), signer);

    // NFT contracts
    mock721Contract1 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer, [
      'Mock NFT 1',
      'MCKNFT1'
    ]);
    mock721Contract2 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer, [
      'Mock NFT 2',
      'MCKNFT2'
    ]);
    mock721Contract3 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer, [
      'Mock NFT 3',
      'MCKNFT3'
    ]);

    // Currency registry
    currencyRegistry = await deployContract(
      'InfinityCurrencyRegistry',
      await ethers.getContractFactory('InfinityCurrencyRegistry'),
      signer
    );

    // Complication registry
    complicationRegistry = await deployContract(
      'InfinityComplicationRegistry',
      await ethers.getContractFactory('InfinityComplicationRegistry'),
      signer
    );

    // Exchange
    exchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange', {
        libraries: {
          Utils: utils.address
        }
      }),
      signer,
      [currencyRegistry.address, complicationRegistry.address, token.address]
    );

    // OB complication
    obComplication = await deployContract(
      'InfinityOrderBookComplication',
      await ethers.getContractFactory('InfinityOrderBookComplication', {
        libraries: {
          Utils: utils.address
        }
      }),
      signer,
      [0, 1_000_000]
    );

    // private sale complication
    privateSaleComplication = await deployContract(
      'InfinityPrivateSaleComplication',
      await ethers.getContractFactory('InfinityPrivateSaleComplication', {
        libraries: {
          Utils: utils.address
        }
      }),
      signer,
      [0, 1_000_000]
    );

    // Infinity treasury
    infinityTreasury = signer.address;

    // Infinity Staker
    infinityStaker = await deployContract('InfinityStaker', await ethers.getContractFactory('InfinityStaker'), signer, [
      token.address,
      infinityTreasury
    ]);

    // Infinity Trading Rewards
    infinityTradingRewards = await deployContract(
      'InfinityTradingRewards',
      await ethers.getContractFactory('contracts/core/InfinityTradingRewards.sol:InfinityTradingRewards'),
      signer,
      [exchange.address, infinityStaker.address, token.address]
    );

    // Infinity Creator Fee Registry
    infinityCreatorsFeeRegistry = await deployContract(
      'InfinityCreatorsFeeRegistry',
      await ethers.getContractFactory('InfinityCreatorsFeeRegistry'),
      signer
    );

    // Infinity Collectors Fee Registry
    infinityCollectorsFeeRegistry = await deployContract(
      'InfinityCollectorsFeeRegistry',
      await ethers.getContractFactory('InfinityCollectorsFeeRegistry'),
      signer
    );

    // Infinity Creators Fee Manager
    mockRoyaltyEngine = await deployContract(
      'MockRoyaltyEngine',
      await ethers.getContractFactory('MockRoyaltyEngine'),
      signer
    );

    // Infinity Creators Fee Manager
    infinityCreatorsFeeManager = await deployContract(
      'InfinityCreatorsFeeManager',
      await ethers.getContractFactory('InfinityCreatorsFeeManager'),
      signer,
      [mockRoyaltyEngine.address, infinityCreatorsFeeRegistry.address]
    );

    // Infinity Collectors Fee Manager
    infinityCollectorsFeeManager = await deployContract(
      'InfinityCollectorsFeeManager',
      await ethers.getContractFactory('InfinityCollectorsFeeManager'),
      signer,
      [infinityCollectorsFeeRegistry.address]
    );

    // Infinity Fee Treasury
    infinityFeeTreasury = await deployContract(
      'InfinityFeeTreasury',
      await ethers.getContractFactory('InfinityFeeTreasury'),
      signer,
      [
        exchange.address,
        infinityStaker.address,
        infinityCreatorsFeeManager.address,
        infinityCollectorsFeeManager.address
      ]
    );

    // add currencies to registry
    await currencyRegistry.addCurrency(token.address);

    // add complications to registry
    await complicationRegistry.addComplication(obComplication.address);
    await complicationRegistry.addComplication(privateSaleComplication.address);

    // send assets
    await token.transfer(signer2.address, INITIAL_SUPPLY.div(2).toString());
    for (let i = 0; i < 20; i++) {
      await mock721Contract1.transferFrom(signer.address, signer2.address, i);
      await mock721Contract2.transferFrom(signer.address, signer2.address, i);
      await mock721Contract3.transferFrom(signer.address, signer2.address, i);
    }
  });

  describe('Setup', () => {
    it('Should init properly', async function () {
      expect(await token.name()).to.equal('Infinity');
      expect(await token.symbol()).to.equal('NFT');
      expect(await token.decimals()).to.equal(18);
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);

      expect(await token.balanceOf(signer.address)).to.equal(INITIAL_SUPPLY.div(2));
      expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2));

      expect(await mock721Contract1.balanceOf(signer.address)).to.equal(30);
      expect(await mock721Contract1.balanceOf(signer2.address)).to.equal(20);

      expect(await mock721Contract2.balanceOf(signer.address)).to.equal(30);
      expect(await mock721Contract2.balanceOf(signer2.address)).to.equal(20);

      expect(await mock721Contract3.balanceOf(signer.address)).to.equal(30);
      expect(await mock721Contract3.balanceOf(signer2.address)).to.equal(20);
    });
  });

  describe('Pre-cliff', () => {
    it('Should not allow advancing directly after deployment', async function () {
      await expect(token.advanceEpoch()).to.be.revertedWith('cliff not passed');
    });
    it('Should not allow advancing even if very close to the cliff', async function () {
      await network.provider.send('evm_increaseTime', [CLIFF_PERIOD.sub(5 * MINUTE).toNumber()]);
      await expect(token.advanceEpoch()).to.be.revertedWith('cliff not passed');
    });
  });
});
