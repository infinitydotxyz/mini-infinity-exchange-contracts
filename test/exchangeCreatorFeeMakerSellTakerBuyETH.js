const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const { deployContract } = require('../tasks/utils');
const { prepareOBOrder, getCurrentSignedOrderPrice, signFormattedOrder } = require('../helpers/orders');
const { nowSeconds, NULL_ADDRESS } = require('@infinityxyz/lib/utils');
const { erc721Abi } = require('../abi/erc721');

describe('Exchange_ETH_Creator_Fee_Maker_Sell_Taker_Buy', function () {
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

  let signer1EthBalance = 0;
  let signer2EthBalance = 0;
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
      const execParams = { complicationAddress: obComplication.address, currencyAddress: NULL_ADDRESS };
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
      const execParams = { complicationAddress: obComplication.address, currencyAddress: NULL_ADDRESS };
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
      const salePriceInEth = parseFloat(ethers.utils.formatEther(salePrice));

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
      signer1EthBalance = parseFloat(ethers.utils.formatEther(await ethers.provider.getBalance(signer1.address)));
      signer2EthBalance = parseFloat(ethers.utils.formatEther(await ethers.provider.getBalance(signer2.address)));

      // perform exchange
      const options = {
        value: salePrice
      };
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder], options);

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
      const feeInEth = parseFloat(ethers.utils.formatEther(fee));
      totalProtocolFees = totalProtocolFees.add(fee);
      expect(await ethers.provider.getBalance(infinityExchange.address)).to.equal(totalProtocolFees);
      signer1EthBalance = signer1EthBalance - salePriceInEth;
      signer2EthBalance = signer2EthBalance + (salePriceInEth - feeInEth);
      const signer1EthBalanceAfter = parseFloat(
        ethers.utils.formatEther(await ethers.provider.getBalance(signer1.address))
      );
      const signer2EthBalanceAfter = parseFloat(
        ethers.utils.formatEther(await ethers.provider.getBalance(signer2.address))
      );
      expect(signer1EthBalanceAfter).to.be.lessThan(signer1EthBalance); // to account for gas
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

  describe('Take_OneCollectionMultipleTokensSell', () => {
    it('Should take valid order with royalty from infinity registry', async function () {
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
      const salePriceInEth = parseFloat(ethers.utils.formatEther(salePrice));

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

      const fee = salePrice.mul(FEE_BPS).div(10000);
      totalProtocolFees = totalProtocolFees.add(fee);
      const creatorFee = salePrice.mul(CREATOR_FEE_BPS).div(10000);
      totalCreatorFees = totalCreatorFees.add(creatorFee);
      const totalFee = creatorFee.add(fee);
      const totalFeeInEth = parseFloat(ethers.utils.formatEther(totalFee));

      totalFeeSoFar = totalProtocolFees;

      const result = await infinityCreatorsFeeManager.getCreatorsFeeInfo(mock721Contract1.address, salePrice);
      const recipient = result[1];
      const bpsSplit1 = result[2];
      const amount = result[3];
      if (!creatorFees[recipient]) {
        creatorFees[recipient] = toBN(0);
      }
      expect(amount).to.equal(creatorFee);
      creatorFees[recipient] = creatorFees[recipient].add(creatorFee);
      // console.log('creatorFees recepient', recipient, creatorFees[recipient]);
      const destBalanceBeforeSale = await ethers.provider.getBalance(recipient);

      // perform exchange
      const options = {
        value: salePrice
      };
      await infinityExchange.connect(signer1).takeOrders([sellOrder], [buyOrder], options);

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
      expect(await ethers.provider.getBalance(infinityExchange.address)).to.equal(totalFeeSoFar);

      const allocatedCreatorFee = toBN(await ethers.provider.getBalance(recipient)).sub(destBalanceBeforeSale);
      expect(allocatedCreatorFee.toString()).to.equal(creatorFees[recipient].toString());

      signer1EthBalance = signer1EthBalance - salePriceInEth;
      signer2EthBalance = signer2EthBalance + (salePriceInEth - totalFeeInEth);
      const signer1EthBalanceAfter = parseFloat(
        ethers.utils.formatEther(await ethers.provider.getBalance(signer1.address))
      );
      const signer2EthBalanceAfter = parseFloat(
        ethers.utils.formatEther(await ethers.provider.getBalance(signer2.address))
      );
      expect(signer1EthBalanceAfter).to.be.lessThan(signer1EthBalance); // to account for gas
      // expect(signer2EthBalanceAfter).to.equal(signer2EthBalance);
    });
  });
});
