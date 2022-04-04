const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const { deployContract } = require('../tasks/utils');
const {
  prepareOBOrder,
  signOBOrder,
  getCurrentSignedOrderPrice,
  approveERC721,
  approveERC20
} = require('../helpers/orders');
const { nowSeconds, trimLowerCase } = require('@infinityxyz/lib/utils');
const { erc721Abi } = require('../abi/erc721');
const { erc20Abi } = require('../abi/erc20');

describe('Exchange', function () {
  let signers,
    signer1,
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
    infinityTreasury,
    infinityStaker,
    infinityTradingRewards,
    infinityFeeTreasury,
    infinityCreatorsFeeRegistry,
    mockRoyaltyEngine,
    infinityCreatorsFeeManager,
    infinityCollectorsFeeRegistry,
    infinityCollectorsFeeManager;

  const buyOrders = [];
  const sellOrders = [];

  const CURATOR_FEE_BPS = 150;
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
    signer1 = signers[0];
    signer2 = signers[1];

    // token
    const tokenArgs = [
      signer1.address,
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
    utils = await deployContract('Utils', await ethers.getContractFactory('Utils'), signer1);

    // NFT contracts
    mock721Contract1 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer1, [
      'Mock NFT 1',
      'MCKNFT1'
    ]);
    mock721Contract2 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer1, [
      'Mock NFT 2',
      'MCKNFT2'
    ]);
    mock721Contract3 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer1, [
      'Mock NFT 3',
      'MCKNFT3'
    ]);

    // Currency registry
    currencyRegistry = await deployContract(
      'InfinityCurrencyRegistry',
      await ethers.getContractFactory('InfinityCurrencyRegistry'),
      signer1
    );

    // Complication registry
    complicationRegistry = await deployContract(
      'InfinityComplicationRegistry',
      await ethers.getContractFactory('InfinityComplicationRegistry'),
      signer1
    );

    // Exchange
    exchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange', {
        libraries: {
          Utils: utils.address
        }
      }),
      signer1,
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
      signer1,
      [0, 1_000_000]
    );

    // Infinity treasury
    infinityTreasury = signer1.address;

    // Infinity Staker
    infinityStaker = await deployContract(
      'InfinityStaker',
      await ethers.getContractFactory('InfinityStaker'),
      signer1,
      [token.address, infinityTreasury]
    );

    // Infinity Trading Rewards
    infinityTradingRewards = await deployContract(
      'InfinityTradingRewards',
      await ethers.getContractFactory('contracts/core/InfinityTradingRewards.sol:InfinityTradingRewards'),
      signer1,
      [exchange.address, infinityStaker.address, token.address]
    );

    // Infinity Creator Fee Registry
    infinityCreatorsFeeRegistry = await deployContract(
      'InfinityCreatorsFeeRegistry',
      await ethers.getContractFactory('InfinityCreatorsFeeRegistry'),
      signer1
    );

    // Infinity Collectors Fee Registry
    infinityCollectorsFeeRegistry = await deployContract(
      'InfinityCollectorsFeeRegistry',
      await ethers.getContractFactory('InfinityCollectorsFeeRegistry'),
      signer1
    );

    // Infinity Creators Fee Manager
    mockRoyaltyEngine = await deployContract(
      'MockRoyaltyEngine',
      await ethers.getContractFactory('MockRoyaltyEngine'),
      signer1
    );

    // Infinity Creators Fee Manager
    infinityCreatorsFeeManager = await deployContract(
      'InfinityCreatorsFeeManager',
      await ethers.getContractFactory('InfinityCreatorsFeeManager'),
      signer1,
      [mockRoyaltyEngine.address, infinityCreatorsFeeRegistry.address]
    );

    // Infinity Collectors Fee Manager
    infinityCollectorsFeeManager = await deployContract(
      'InfinityCollectorsFeeManager',
      await ethers.getContractFactory('InfinityCollectorsFeeManager'),
      signer1,
      [infinityCollectorsFeeRegistry.address]
    );

    // Infinity Fee Treasury
    infinityFeeTreasury = await deployContract(
      'InfinityFeeTreasury',
      await ethers.getContractFactory('InfinityFeeTreasury'),
      signer1,
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

    // set infinity fee treasury on exchange
    await exchange.updateInfinityFeeTreasury(infinityFeeTreasury.address);

    // send assets
    await token.transfer(signer2.address, INITIAL_SUPPLY.div(2).toString());
    for (let i = 0; i < 20; i++) {
      await mock721Contract1.transferFrom(signer1.address, signer2.address, i);
      await mock721Contract2.transferFrom(signer1.address, signer2.address, i);
      await mock721Contract3.transferFrom(signer1.address, signer2.address, i);
    }
  });

  describe('Setup', () => {
    it('Should init properly', async function () {
      expect(await token.name()).to.equal('Infinity');
      expect(await token.symbol()).to.equal('NFT');
      expect(await token.decimals()).to.equal(18);
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);

      expect(await token.balanceOf(signer1.address)).to.equal(INITIAL_SUPPLY.div(2));
      expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2));

      expect(await mock721Contract1.balanceOf(signer1.address)).to.equal(30);
      expect(await mock721Contract1.balanceOf(signer2.address)).to.equal(20);

      expect(await mock721Contract2.balanceOf(signer1.address)).to.equal(30);
      expect(await mock721Contract2.balanceOf(signer2.address)).to.equal(20);

      expect(await mock721Contract3.balanceOf(signer1.address)).to.equal(30);
      expect(await mock721Contract3.balanceOf(signer2.address)).to.equal(20);
    });
  });

  // ================================================== MAKE BUY ORDERS ==================================================

  // one specific collection, one specific token, max price
  describe('OneCollectionOneTokenBuy', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer1.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          // tokenIds: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
          tokens: [{ tokenId: 0, numTokens: 1 }]
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = 1;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: false,
        signerAddress: user.address,
        numItems: 1,
        startPrice: ethers.utils.parseEther('1'),
        endPrice: ethers.utils.parseEther('1'),
        startTime: nowSeconds(),
        endTime: nowSeconds().add(10 * 60),
        minBpsToSeller: 9000,
        nonce,
        nfts,
        execParams,
        extraParams
      };
      const signedOrder = await prepareOBOrder(user, chainId, signer1, order, exchange, infinityFeeTreasury.address);
      expect(signedOrder).to.not.be.undefined;
      buyOrders.push(signedOrder);
    });
  });

  // one specific collection, multiple specific tokens, max aggregate price

  // one specific collection, any one token, max price

  // one specific collection, any multiple tokens, max aggregate price, min number of tokens

  // multiple specific collections, multiple specific tokens per collection, max aggregate price

  // multiple specific collections, any multiple tokens per collection, max aggregate price, min aggregate number of tokens

  // any collection, any one token, max price

  // any collection, any multiple tokens, max aggregate price, min aggregate number of tokens

  // ================================================== MAKE SELL ORDERS ==================================================

  // one specific collection, one specific token, min price

  // one specific collection, multiple specific tokens, min aggregate price

  // one specific collection, any one token, min price

  // one specific collection, any multiple tokens, min aggregate price, max number of tokens

  // multiple specific collections, multiple specific tokens per collection, min aggregate price

  // multiple specific collections, any multiple tokens per collection, min aggregate price, max aggregate number of tokens

  // any collection, any one token, min price

  // any collection, any multiple tokens, min aggregate price, max aggregate number of tokens

  // ================================================== MATCH ORDERS ==================================================

  // ================================================== TAKE ORDERS ===================================================
  describe('Take_OneCollectionOneTokenBuy', () => {
    it('Should take valid order', async function () {
      const buyOrder = buyOrders[0];
      const chainId = network.config.chainId;
      const contractAddress = exchange.address;
      const isSellOrder = true;
      const signerAddress = signer2.address;
      const dataHash = buyOrder.dataHash;
      const constraints = buyOrder.constraints;
      const nfts = buyOrder.nfts;
      const execParams = buyOrder.execParams;
      const extraParams = buyOrder.extraParams;

      // approve NFTs
      await approveERC721(signerAddress, buyOrder.nfts, signer2, exchange.address);

      // sign order
      const sig = await signOBOrder(chainId, contractAddress, isSellOrder, signer2, dataHash, extraParams);
      const sellOrder = {
        isSellOrder,
        signer: signerAddress,
        dataHash,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig
      };

      const isSigValid = await exchange.verifyOrderSig(sellOrder);
      if (!isSigValid) {
        console.error('take order signature is invalid');
      } else {
        // owners before sale
        for (const item of nfts) {
          const collection = item.collection;
          const contract = new ethers.Contract(collection, erc721Abi, signer1);
          for (const token of item.tokens) {
            const tokenId = token.tokenId;
            expect(await contract.ownerOf(tokenId)).to.equal(signer2.address);
          }
        }

        // sale price
        const salePrice = getCurrentSignedOrderPrice(sellOrder);

        // balance before sale
        expect(await token.balanceOf(signer1.address)).to.equal(INITIAL_SUPPLY.div(2));
        expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2));

        // perform exchange
        await exchange.connect(signer2).takeOrders([buyOrder], [sellOrder], false, false);

        // owners after sale
        for (const item of nfts) {
          const collection = item.collection;
          const contract = new ethers.Contract(collection, erc721Abi, signer1);
          for (const token of item.tokens) {
            const tokenId = token.tokenId;
            expect(await contract.ownerOf(tokenId)).to.equal(signer1.address);
          }
        }

        // balance after sale
        const fee = salePrice.mul(CURATOR_FEE_BPS).div(10000);
        expect(await token.balanceOf(infinityFeeTreasury.address)).to.equal(fee);
        expect(await token.balanceOf(signer1.address)).to.equal(INITIAL_SUPPLY.div(2).sub(salePrice));
        expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2).add(salePrice.sub(fee)));
      }
    });
  });

  // ================================================== CANCEL ORDERS =================================================
});
