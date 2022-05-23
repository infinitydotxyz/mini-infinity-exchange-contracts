const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const { deployContract } = require('../tasks/utils');
const {
  prepareOBOrder,
  signOBOrder,
  getCurrentSignedOrderPrice,
  approveERC721,
  approveERC20,
  signFormattedOrder
} = require('../helpers/orders');
const { nowSeconds, trimLowerCase, NULL_ADDRESS } = require('@infinityxyz/lib/utils');
const { erc721Abi } = require('../abi/erc721');
const { erc20Abi } = require('../abi/erc20');

describe('Exchange_Creator_Fee_Maker_Sell_Taker_Buy', function () {
  let signers,
    signer1,
    signer2,
    signer3,
    signer4,
    token,
    infinityExchange,
    mock721Contract1,
    mock721Contract3,
    obComplication,
    infinityCreatorsFeeRegistry,
    infinityCreatorsFeeManager;

  const sellOrders = [];

  let signer1Balance = toBN(0);
  let signer2Balance = toBN(0);
  let totalProtocolFees = toBN(0);
  let totalCreatorFees = toBN(0);
  let totalFeeSoFar = toBN(0);
  let creatorFees = {};
  let orderNonce = 0;
  let numTakeOrders = -1;

  const FEE_BPS = 250;
  const CREATOR_FEE_BPS = 200;
  const UNIT = toBN(1e18);
  const INITIAL_SUPPLY = toBN(1_000_000).mul(UNIT);

  const totalNFTSupply = 100;
  const numNFTsToTransfer = 50;
  const numNFTsLeft = totalNFTSupply - numNFTsToTransfer;

  function toBN(val) {
    return ethers.BigNumber.from(val.toString());
  }

  function toFloor(val) {
    return toBN(Math.floor(val));
  }

  before(async () => {
    // signers
    signers = await ethers.getSigners();
    signer1 = signers[0];
    signer2 = signers[1];
    signer3 = signers[2];
    signer4 = signers[3];
    // token
    token = await deployContract('MockERC20', await ethers.getContractFactory('MockERC20'), signers[0]);

    // NFT contracts
    mock721Contract1 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer1, [
      'Mock NFT 1',
      'MCKNFT1'
    ]);
    mock721Contract3 = await deployContract('MockERC721', await ethers.getContractFactory('MockERC721'), signer1, [
      'Mock NFT 3',
      'MCKNFT3'
    ]);

    // Infinity Creator Fee Registry
    infinityCreatorsFeeRegistry = await deployContract(
      'InfinityCreatorsFeeRegistry',
      await ethers.getContractFactory('InfinityCreatorsFeeRegistry'),
      signer1
    );

    // Infinity Creators Fee Manager
    infinityCreatorsFeeManager = await deployContract(
      'InfinityCreatorsFeeManager',
      await ethers.getContractFactory('InfinityCreatorsFeeManager'),
      signer1,
      [infinityCreatorsFeeRegistry.address]
    );

    // Exchange
    infinityExchange = await deployContract(
      'InfinityExchange',
      await ethers.getContractFactory('InfinityExchange'),
      signer1,
      [token.address, signer3.address, infinityCreatorsFeeManager.address]
    );

    // OB complication
    obComplication = await deployContract(
      'InfinityOrderBookComplication',
      await ethers.getContractFactory('InfinityOrderBookComplication'),
      signer1,
      [FEE_BPS, 1_000_000]
    );

    // add currencies to registry
    await infinityExchange.addCurrency(token.address);
    await infinityExchange.addCurrency(NULL_ADDRESS);

    // add complications to registry
    await infinityExchange.addComplication(obComplication.address);

    // set infinity fee treasury on exchange
    await infinityCreatorsFeeRegistry.updateCreatorsFeeManager(infinityCreatorsFeeManager.address);

    // send assets
    await token.transfer(signer2.address, INITIAL_SUPPLY.div(2).toString());
    for (let i = 0; i < numNFTsToTransfer; i++) {
      await mock721Contract1.transferFrom(signer1.address, signer2.address, i);
      await mock721Contract3.transferFrom(signer1.address, signer2.address, i);
    }
  });

  describe('Setup', () => {
    it('Should init properly', async function () {
      expect(await token.decimals()).to.equal(18);
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);

      expect(await token.balanceOf(signer1.address)).to.equal(INITIAL_SUPPLY.div(2));
      expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2));

      expect(await mock721Contract1.balanceOf(signer1.address)).to.equal(numNFTsLeft);
      expect(await mock721Contract1.balanceOf(signer2.address)).to.equal(numNFTsToTransfer);

      expect(await mock721Contract3.balanceOf(signer1.address)).to.equal(numNFTsLeft);
      expect(await mock721Contract3.balanceOf(signer2.address)).to.equal(numNFTsToTransfer);
    });
  });

  // ================================================== MAKE SELL ORDERS ==================================================

  // one specific collection, one specific token, min price
  describe('OneCollectionOneTokenSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: [{ tokenId: 0, numTokens: 1 }]
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      let numItems = 0;
      for (const nft of nfts) {
        numItems += nft.tokens.length;
      }
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // one specific collection, multiple specific tokens, min aggregate price
  describe('OneCollectionMultipleTokensSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: [
            { tokenId: 1, numTokens: 1 },
            { tokenId: 2, numTokens: 1 },
            { tokenId: 3, numTokens: 1 }
          ]
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      let numItems = 0;
      for (const nft of nfts) {
        numItems += nft.tokens.length;
      }
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // one specific collection, any one token, min price
  describe('OneCollectionAnyOneTokenSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: []
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // one specific collection, any multiple tokens, min aggregate price, max number of tokens
  describe('OneCollectionAnyMultipleTokensSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: []
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems: 4,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // multiple specific collections, multiple specific tokens per collection, min aggregate price
  describe('MultipleCollectionsMultipleTokensSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: [{ tokenId: 11, numTokens: 1 }]
        },
        {
          collection: mock721Contract3.address,
          tokens: [
            { tokenId: 0, numTokens: 1 },
            { tokenId: 1, numTokens: 1 },
            { tokenId: 2, numTokens: 1 }
          ]
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      let numItems = 0;
      for (const nft of nfts) {
        numItems += nft.tokens.length;
      }
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // multiple specific collections, any multiple tokens per collection, min aggregate price, max aggregate number of tokens
  describe('MultipleCollectionsAnyTokensSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [
        {
          collection: mock721Contract1.address,
          tokens: []
        },
        {
          collection: mock721Contract3.address,
          tokens: []
        }
      ];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems: 5,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // any collection, any one token, min price
  describe('AnyCollectionAnyOneTokenSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
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
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // any collection, any multiple tokens, min aggregate price, max aggregate number of tokens
  describe('AnyCollectionAnyMultipleTokensSell', () => {
    it('Signed order should be valid', async function () {
      const user = {
        address: signer2.address
      };
      const chainId = network.config.chainId;
      const nfts = [];
      const execParams = { complicationAddress: obComplication.address, currencyAddress: token.address };
      const extraParams = {};
      const nonce = ++orderNonce;
      const orderId = ethers.utils.solidityKeccak256(['address', 'uint256', 'uint256'], [user.address, nonce, chainId]);
      const order = {
        id: orderId,
        chainId,
        isSellOrder: true,
        signerAddress: user.address,
        numItems: 12,
        startPrice: ethers.utils.parseEther('5'),
        endPrice: ethers.utils.parseEther('5'),
        startTime: nowSeconds(),
        endTime: nowSeconds().add(10 * 60),
        minBpsToSeller: 9000,
        nonce,
        nfts,
        execParams,
        extraParams
      };
      const signedOrder = await prepareOBOrder(user, chainId, signer2, order, infinityExchange);
      expect(signedOrder).to.not.be.undefined;
      sellOrders.push(signedOrder);
    });
  });

  // ================================================== TAKE SELL ORDERS ===================================================

  describe('Take_OneCollectionOneTokenSell', () => {
    it('Should take valid order with no royalty', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const nfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // approve currency
      const salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

      // owners before sale
      for (const item of nfts) {
        const collection = item.collection;
        const contract = new ethers.Contract(collection, erc721Abi, signer1);
        for (const token of item.tokens) {
          const tokenId = token.tokenId;
          expect(await contract.ownerOf(tokenId)).to.equal(signer2.address);
        }
      }

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(INITIAL_SUPPLY.div(2));
      expect(await token.balanceOf(signer2.address)).to.equal(INITIAL_SUPPLY.div(2));

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalProtocolFees);
      signer1Balance = INITIAL_SUPPLY.div(2).sub(salePrice);
      signer2Balance = INITIAL_SUPPLY.div(2).add(salePrice.sub(fee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Take_OneCollectionMultipleTokensSell', () => {
    it('Should take valid order with no royalty', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const nfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // approve currency
      const salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

      // owners before sale
      for (const item of nfts) {
        const collection = item.collection;
        const contract = new ethers.Contract(collection, erc721Abi, signer1);
        for (const token of item.tokens) {
          const tokenId = token.tokenId;
          expect(await contract.ownerOf(tokenId)).to.equal(signer2.address);
        }
      }

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      totalFeeSoFar = totalProtocolFees;
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalFeeSoFar);

      signer1Balance = signer1Balance.sub(salePrice);
      signer2Balance = signer2Balance.add(salePrice.sub(fee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Set_Royalty_In_InfinityRoyaltyRegistry', () => {
    it('Should set royalty', async function () {
      await infinityCreatorsFeeManager
        .connect(signer1)
        .setupCollectionForCreatorFeeShare(mock721Contract1.address, signer3.address, CREATOR_FEE_BPS);
      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        ethers.utils.parseEther('1')
      );
      const setter = result[0];
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      const calcRoyalty1 = ethers.utils.parseEther('1').mul(CREATOR_FEE_BPS).div(10000);
      expect(setter).to.equal(signer1.address);
      expect(dest1).to.equal(signer3.address);
      expect(bpsSplit1).to.equal(CREATOR_FEE_BPS);
      expect(amount1.toString()).to.equal(calcRoyalty1);
    });
  });

  describe('Take_OneCollectionAnyOneTokenSell', () => {
    it('Should take valid order with royalty from infinity royalty registry', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const sellOrderNfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // form matching nfts
      const nfts = [];
      for (const buyOrderNft of sellOrderNfts) {
        const collection = buyOrderNft.collection;
        const nft = {
          collection,
          tokens: [
            {
              tokenId: 4,
              numTokens: 1
            }
          ]
        };
        nfts.push(nft);
      }

      // approve currency
      let salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

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
      salePrice = getCurrentSignedOrderPrice(buyOrder);

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);

      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      const creatorFee = salePrice.mul(CREATOR_FEE_BPS).div(10000);
      totalCreatorFees = totalCreatorFees.add(creatorFee);
      const totalFee = creatorFee.add(fee);
      totalFeeSoFar = totalProtocolFees;

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(mock721Contract1.address, salePrice);
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      if (!creatorFees[dest1]) {
        creatorFees[dest1] = toBN(0);
      }
      expect(amount1).to.equal(creatorFee.mul(bpsSplit1).div(CREATOR_FEE_BPS));
      creatorFees[dest1] = creatorFees[dest1].add(amount1);
      const destBalanceBeforeSale = await token.balanceOf(dest1);
      // console.log('creatorFees dest1', dest1, creatorFees[dest1]);

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalFeeSoFar);

      const allocatedCreatorFee1 = toBN(await token.balanceOf(dest1)).sub(destBalanceBeforeSale);
      expect(allocatedCreatorFee1.toString()).to.equal(creatorFees[dest1].toString());

      signer1Balance = signer1Balance.sub(salePrice);
      signer2Balance = signer2Balance.add(salePrice.sub(totalFee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Update_Royalty_In_InfinityRoyaltyRegistry', () => {
    it('Should update royalty', async function () {
      await infinityCreatorsFeeManager
        .connect(signer1)
        .setupCollectionForCreatorFeeShare(mock721Contract1.address, signer4.address, CREATOR_FEE_BPS);
      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        ethers.utils.parseEther('1')
      );
      const setter = result[0];
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      const calcRoyalty1 = ethers.utils.parseEther('1').mul(CREATOR_FEE_BPS).div(10000);
      expect(setter).to.equal(signer1.address);
      expect(dest1).to.equal(signer4.address);
      expect(bpsSplit1).to.equal(CREATOR_FEE_BPS);
      expect(amount1.toString()).to.equal(calcRoyalty1);
    });
  });

  describe('Take_OneCollectionAnyMultipleTokensSell', () => {
    it('Should take valid order with updated royalty from infinity registry', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const sellOrderNfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // form matching nfts
      const nfts = [];
      for (const sellOrderNft of sellOrderNfts) {
        const collection = sellOrderNft.collection;
        const nft = {
          collection,
          tokens: [
            {
              tokenId: 5,
              numTokens: 1
            },
            {
              tokenId: 6,
              numTokens: 1
            },
            {
              tokenId: 7,
              numTokens: 1
            },
            {
              tokenId: 8,
              numTokens: 1
            }
          ]
        };
        nfts.push(nft);
      }

      // approve currency
      let salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

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
      salePrice = getCurrentSignedOrderPrice(buyOrder);

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);

      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      const creatorFee = salePrice.mul(CREATOR_FEE_BPS).div(10000);
      totalCreatorFees = totalCreatorFees.add(creatorFee);
      const totalFee = creatorFee.add(fee);
      totalFeeSoFar = totalProtocolFees;

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(mock721Contract1.address, salePrice);
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      if (!creatorFees[dest1]) {
        creatorFees[dest1] = toBN(0);
      }
      expect(amount1).to.equal(creatorFee.mul(bpsSplit1).div(CREATOR_FEE_BPS));
      creatorFees[dest1] = creatorFees[dest1].add(amount1);
      const destBalanceBeforeSale = await token.balanceOf(dest1);

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalFeeSoFar);

      const allocatedCreatorFee1 = toBN(await token.balanceOf(dest1)).sub(destBalanceBeforeSale);
      expect(allocatedCreatorFee1.toString()).to.equal(creatorFees[dest1].toString());

      signer1Balance = signer1Balance.sub(salePrice);
      signer2Balance = signer2Balance.add(salePrice.sub(totalFee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Take_MultipleCollectionsMultipleTokensSell', () => {
    it('Should take valid order from infinity registry', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const nfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // approve currency
      let salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

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
      salePrice = getCurrentSignedOrderPrice(buyOrder);

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);

      const numColls = nfts.length;
      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      // console.log('salePrice', salePrice.toString());
      // console.log('sale price by numColls', numColls, salePrice.div(numColls).toString());
      const creatorFeeInfinityRegistry = salePrice.div(numColls).mul(CREATOR_FEE_BPS).div(10000);
      totalCreatorFees = totalCreatorFees.add(creatorFeeInfinityRegistry);
      // console.log('creatorFeeInfinityRegistry', creatorFeeInfinityRegistry.toString());
      // console.log('creatorFeeIerc2981', creatorFeeIerc2981.toString());
      // console.log('creatorFeeRoyaltyEngine', creatorFeeRoyaltyEngine.toString());

      const totalFee = fee.add(creatorFeeInfinityRegistry);
      // console.log(
      //   'fee',
      //   fee,
      //   'total fee',
      //   totalFee.toString(),
      //   'totalProtocolFees',
      //   totalProtocolFees.toString(),
      //   'totalCreatorFees',
      //   totalCreatorFees.toString()
      // );
      totalFeeSoFar = totalProtocolFees;

      const result1 = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        toFloor(salePrice.div(numColls))
      );
      const dest1 = result1[1];
      const bps1 = result1[2];
      const amount1 = result1[3];
      if (!creatorFees[dest1]) {
        creatorFees[dest1] = toBN(0);
      }
      expect(amount1).to.equal(creatorFeeInfinityRegistry.mul(bps1).div(CREATOR_FEE_BPS));
      creatorFees[dest1] = creatorFees[dest1].add(amount1);
      const destBalanceBeforeSale = await token.balanceOf(dest1);
      // console.log(
      //   'creator fees dest1',
      //   dest1,
      //   creatorFees[dest1],
      //   'creator fees dest2',
      //   dest2,
      //   creatorFees[dest2],
      //   'creator fees dest2_1',
      //   dest2_1,
      //   creatorFees[dest2_1]
      // );

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalFeeSoFar);

      const allocatedCreatorFee1 = await token.balanceOf(dest1);
      expect(allocatedCreatorFee1.toString()).to.equal(creatorFees[dest1].toString());

      signer1Balance = signer1Balance.sub(salePrice);
      signer2Balance = signer2Balance.add(salePrice.sub(totalFee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Take_MultipleCollectionsAnyTokensSell', () => {
    it('Should take valid order from infinity registry', async function () {
      const sellOrder = sellOrders[++numTakeOrders];
      const chainId = network.config.chainId;
      const contractAddress = infinityExchange.address;
      const isSellOrder = false;

      const constraints = sellOrder.constraints;
      const sellOrderNfts = sellOrder.nfts;
      const execParams = sellOrder.execParams;
      const extraParams = sellOrder.extraParams;

      // form matching nfts
      const nfts = [];
      let i = 0;
      for (const buyOrderNft of sellOrderNfts) {
        ++i;
        const collection = buyOrderNft.collection;
        let nft;
        if (i === 1) {
          nft = {
            collection,
            tokens: [
              {
                tokenId: 20,
                numTokens: 1
              },
              {
                tokenId: 21,
                numTokens: 1
              }
            ]
          };
        } else {
          nft = {
            collection,
            tokens: [
              {
                tokenId: 10,
                numTokens: 1
              },
              {
                tokenId: 11,
                numTokens: 1
              },
              {
                tokenId: 12,
                numTokens: 1
              }
            ]
          };
        }

        nfts.push(nft);
      }

      // approve currency
      let salePrice = getCurrentSignedOrderPrice(sellOrder);
      await approveERC20(signer1.address, execParams[1], salePrice, signer1, infinityExchange.address);

      // sign order
      const buyOrder = {
        isSellOrder,
        signer: signer1.address,
        extraParams,
        nfts,
        constraints,
        execParams,
        sig: ''
      };
      buyOrder.sig = await signFormattedOrder(chainId, contractAddress, buyOrder, signer1);

      const isSigValid = await infinityExchange.verifyOrderSig(buyOrder);
      expect(isSigValid).to.equal(true);

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
      salePrice = getCurrentSignedOrderPrice(buyOrder);

      // balance before sale
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);

      const numColls = nfts.length;
      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      const creatorFeeInfinityRegistry = salePrice.div(numColls).mul(CREATOR_FEE_BPS).div(10000);
      totalCreatorFees = totalCreatorFees.add(creatorFeeInfinityRegistry);

      const totalFee = fee.add(creatorFeeInfinityRegistry);
      totalFeeSoFar = totalProtocolFees;

      const result1 = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        toFloor(salePrice.div(numColls))
      );
      const dest1 = result1[1];
      const bpsSplit1 = result1[2];
      const amount1 = result1[3];
      if (!creatorFees[dest1]) {
        creatorFees[dest1] = toBN(0);
      }
      expect(amount1).to.equal(creatorFeeInfinityRegistry.mul(bpsSplit1).div(CREATOR_FEE_BPS));
      creatorFees[dest1] = creatorFees[dest1].add(amount1);
      const destBalanceBeforeSale = await token.balanceOf(dest1);

      // estimate gas
      const numTokens = buyOrder.nfts.reduce((acc, nft) => {
        return (
          acc +
          nft.tokens.reduce((acc, token) => {
            return acc + token.numTokens;
          }, 0)
        );
      }, 0);
      console.log('total numTokens in order', numTokens);
      const gasEstimate = await infinityExchange.connect(signer1).estimateGas.takeOrders([sellOrder], [buyOrder]);
      console.log('gasEstimate', gasEstimate.toNumber());
      console.log('gasEstimate per token', gasEstimate / numTokens);

      // perform exchange
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder]);

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
      expect(await token.balanceOf(infinityExchange.address)).to.equal(totalFeeSoFar);

      const allocatedCreatorFee1 = await token.balanceOf(dest1);
      expect(allocatedCreatorFee1.toString()).to.equal(creatorFees[dest1].toString());

      signer1Balance = signer1Balance.sub(salePrice);
      signer2Balance = signer2Balance.add(salePrice.sub(totalFee));
      expect(await token.balanceOf(signer1.address)).to.equal(signer1Balance);
      expect(await token.balanceOf(signer2.address)).to.equal(signer2Balance);
    });
  });

  describe('Try_SetBps_TooHigh', () => {
    it('Should not succeed', async function () {
      await expect(
        infinityCreatorsFeeManager
          .connect(signer1)
          .setupCollectionForCreatorFeeShare(mock721Contract1.address, signer2.address, CREATOR_FEE_BPS * 2)
      ).to.be.revertedWith('bps too high');

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        ethers.utils.parseEther('1')
      );
      const setter = result[0];
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      const calcRoyalty1 = ethers.utils.parseEther('1').mul(CREATOR_FEE_BPS).div(10000);
      expect(setter).to.equal(signer1.address);
      expect(dest1).to.equal(signer4.address); // old dest
      expect(bpsSplit1).to.equal(CREATOR_FEE_BPS);
      expect(amount1.toString()).to.equal(calcRoyalty1);
    });
  });

  describe('Try_Setup_Collection_NonOwner', () => {
    it('Should not succeed', async function () {
      await expect(
        infinityCreatorsFeeManager
          .connect(signer2)
          .setupCollectionForCreatorFeeShare(mock721Contract1.address, signer2.address, CREATOR_FEE_BPS / 4)
      ).to.be.revertedWith('unauthorized');

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        ethers.utils.parseEther('1')
      );
      const setter = result[0];
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      const calcRoyalty1 = ethers.utils.parseEther('1').mul(CREATOR_FEE_BPS).div(10000);
      expect(setter).to.equal(signer1.address);
      expect(dest1).to.equal(signer4.address);
      expect(bpsSplit1).to.equal(CREATOR_FEE_BPS);
      expect(amount1.toString()).to.equal(calcRoyalty1);
    });
  });

  describe('Setup_Collection_NonOwner_ButAdmin', () => {
    it('Should succeed', async function () {
      await infinityCreatorsFeeManager
        .connect(signer1)
        .setupCollectionForCreatorFeeShare(mock721Contract1.address, signer3.address, CREATOR_FEE_BPS / 4);

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(
        mock721Contract1.address,
        ethers.utils.parseEther('1')
      );
      const setter = result[0];
      const dest1 = result[1];
      const bpsSplit1 = result[2];
      const amount1 = result[3];
      const calcRoyalty1 = ethers.utils
        .parseEther('1')
        .mul(CREATOR_FEE_BPS / 4)
        .div(10000);
      expect(setter).to.equal(signer1.address);
      expect(dest1).to.equal(signer3.address);
      expect(bpsSplit1).to.equal(CREATOR_FEE_BPS / 4);
      expect(amount1.toString()).to.equal(calcRoyalty1);
    });
  });
});
