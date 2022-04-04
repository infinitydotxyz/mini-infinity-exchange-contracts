import { BigNumber, BigNumberish, BytesLike, constants, Contract } from 'ethers';
import { defaultAbiCoder, keccak256, solidityKeccak256, splitSignature, _TypedDataEncoder } from 'ethers/lib/utils';
import { infinityExchangeAbi } from '../abi/infinityExchange';
import { erc721Abi } from '../abi/erc721';
import { nowSeconds, trimLowerCase } from '@infinityxyz/lib/utils';
import { erc20Abi } from '../abi/erc20';
import { JsonRpcSigner } from '@ethersproject/providers';

// types
export type User = {
  address: string;
};

export interface TokenInfo {
  tokenId: BigNumberish;
  numTokens: BigNumberish;
}

export interface OrderItem {
  collection: string;
  tokens: TokenInfo[];
}

export interface ExecParams {
  complicationAddress: string;
  currencyAddress: string;
}

export interface ExtraParams {
  buyer?: string;
}

export interface OBOrder {
  id: string;
  chainId: BigNumberish;
  isSellOrder: boolean;
  signerAddress: string;
  numItems: BigNumberish;
  startPrice: BigNumberish;
  endPrice: BigNumberish;
  startTime: BigNumberish;
  endTime: BigNumberish;
  minBpsToSeller: BigNumberish;
  nonce: BigNumberish;
  nfts: OrderItem[];
  execParams: ExecParams;
  extraParams: ExtraParams;
}

export interface SignedOBOrder {
  isSellOrder: boolean;
  signer: string;
  dataHash: BytesLike;
  constraints: BigNumberish[];
  nfts: OrderItem[];
  execParams: string[];
  extraParams: BytesLike;
  sig: BytesLike;
}

// constants
const NULL_ADDRESS = '0x0000000000000000000000000000000000000000';

export const getCurrentOrderPrice = (order: OBOrder): BigNumber => {
  const startTime = BigNumber.from(order.startTime);
  const endTime = BigNumber.from(order.endTime);
  const startPrice = BigNumber.from(order.startPrice);
  const endPrice = BigNumber.from(order.endPrice);
  const duration = endTime.sub(startTime);
  let priceDiff = startPrice.sub(endPrice);
  if (priceDiff.eq(0) || duration.eq(0)) {
    return startPrice;
  }
  const elapsedTime = BigNumber.from(nowSeconds()).sub(startTime);
  const portion = elapsedTime.gt(duration) ? 1 : elapsedTime.div(duration);
  priceDiff = priceDiff.mul(portion);
  return startPrice.sub(priceDiff);
};

export const getCurrentSignedOrderPrice = (order: SignedOBOrder): BigNumber => {
  const startPrice = BigNumber.from(order.constraints[1]);
  const endPrice = BigNumber.from(order.constraints[2]);
  const startTime = BigNumber.from(order.constraints[3]);
  const endTime = BigNumber.from(order.constraints[4]);
  const duration = endTime.sub(startTime);
  let priceDiff = startPrice.sub(endPrice);
  if (priceDiff.eq(0) || duration.eq(0)) {
    return startPrice;
  }
  const elapsedTime = BigNumber.from(nowSeconds()).sub(startTime);
  const portion = elapsedTime.gt(duration) ? 1 : elapsedTime.div(duration);
  priceDiff = priceDiff.mul(portion);
  return startPrice.sub(priceDiff);
};

// Orderbook orders
export async function prepareOBOrder(
  user: User,
  chainId: BigNumberish,
  signer: JsonRpcSigner,
  order: OBOrder,
  infinityExchange: Contract,
  infinityFeeTreasuryAddress: string
): Promise<SignedOBOrder | undefined> {
  // check if order is still valid
  const validOrder = await isOrderValid(user, order, infinityExchange, signer);
  if (!validOrder) {
    return undefined;
  }

  // grant approvals
  const approvals = await grantApprovals(user, order, signer, infinityExchange.address, infinityFeeTreasuryAddress);
  if (!approvals) {
    return undefined;
  }

  // construct order
  const constructedOBOrder = await constructOBOrder(chainId, infinityExchange.address, signer, order);

  console.log('Verifying signature');
  const isSigValid = await infinityExchange.verifyOrderSig(constructedOBOrder);
  if (!isSigValid) {
    return undefined;
  }
  return constructedOBOrder;
}

export async function isOrderValid(
  user: User,
  order: OBOrder,
  infinityExchange: Contract,
  signer: JsonRpcSigner
): Promise<boolean> {
  // check timestamps
  const startTime = BigNumber.from(order.startTime);
  const endTime = BigNumber.from(order.endTime);
  const now = nowSeconds();
  if (now.lt(startTime) || now.gt(endTime)) {
    console.error('Order timestamps are not valid');
    return false;
  }

  // check if nonce is valid
  const isNonceValid = await infinityExchange.isNonceValid(user.address, order.nonce);
  console.log('Nonce valid:', isNonceValid);
  if (!isNonceValid) {
    console.error('Order nonce is not valid');
    return false;
  }

  // check on chain ownership
  if (order.isSellOrder) {
    const isCurrentOwner = await checkOnChainOwnership(user, order, signer);
    if (!isCurrentOwner) {
      return false;
    }
  }

  // default
  return true;
}

export async function grantApprovals(
  user: User,
  order: OBOrder,
  signer: JsonRpcSigner,
  exchange: string,
  infinityFeeTreasuryAddress: string
): Promise<boolean> {
  try {
    console.log('Granting approvals');
    if (!order.isSellOrder) {
      // approve currencies
      const currentPrice = getCurrentOrderPrice(order);
      await approveERC20(
        user.address,
        order.execParams.currencyAddress,
        currentPrice,
        signer,
        infinityFeeTreasuryAddress
      );
    } else {
      // approve collections
      await approveERC721(user.address, order.nfts, signer, exchange);
    }
    return true;
  } catch (e) {
    console.error(e);
    return false;
  }
}

export async function approveERC20(
  user: string,
  currencyAddress: string,
  price: BigNumberish,
  signer: JsonRpcSigner,
  infinityFeeTreasuryAddress: string
) {
  try {
    console.log('Granting ERC20 approval');
    if (currencyAddress !== NULL_ADDRESS) {
      const contract = new Contract(currencyAddress, erc20Abi, signer);
      const allowance = BigNumber.from(await contract.allowance(user, infinityFeeTreasuryAddress));
      if (allowance.lt(price)) {
        await contract.approve(infinityFeeTreasuryAddress, constants.MaxUint256);
      }
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    console.error('failed granting erc20 approvals');
    throw new Error(e);
  }
}

export async function approveERC721(user: string, items: OrderItem[], signer: JsonRpcSigner, exchange: string) {
  try {
    console.log('Granting ERC721 approval');
    for (const item of items) {
      const collection = item.collection;
      const contract = new Contract(collection, erc721Abi, signer);
      const isApprovedForAll = await contract.isApprovedForAll(user, exchange);
      if (!isApprovedForAll) {
        await contract.setApprovalForAll(exchange, true);
      }
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    console.error('failed granting erc721 approvals');
    throw new Error(e);
  }
}

export async function checkOnChainOwnership(user: User, order: OBOrder, signer: JsonRpcSigner): Promise<boolean> {
  console.log('Checking on chain ownership');
  let result = true;
  for (const nft of order.nfts) {
    const collection = nft.collection;
    const contract = new Contract(collection, erc721Abi, signer);
    for (const token of nft.tokens) {
      result = result && (await checkERC721Ownership(user, contract, token.tokenId));
    }
  }
  return result;
}

export async function checkERC721Ownership(user: User, contract: Contract, tokenId: BigNumberish): Promise<boolean> {
  try {
    console.log('Checking ERC721 on chain ownership');
    const owner = trimLowerCase(await contract.ownerOf(tokenId));
    if (owner !== trimLowerCase(user.address)) {
      // todo: should continue to check if other nfts are owned
      console.error('Order on chain ownership check failed');
      return false;
    }
  } catch (e) {
    console.error('Failed on chain ownership check; is collection ERC721 ?', e);
    return false;
  }
  return true;
}

export async function constructOBOrder(
  chainId: BigNumberish,
  contractAddress: string,
  signer: JsonRpcSigner,
  order: OBOrder
): Promise<SignedOBOrder> {
  const domain = {
    name: 'InfinityExchange',
    version: '1',
    chainId: chainId,
    verifyingContract: contractAddress
  };

  const types = {
    Order: [
      { name: 'isSellOrder', type: 'bool' },
      { name: 'signer', type: 'address' },
      { name: 'dataHash', type: 'bytes32' },
      { name: 'extraParams', type: 'bytes' }
    ]
  };

  const constraints = [
    order.numItems,
    order.startPrice,
    order.endPrice,
    order.startTime,
    order.endTime,
    order.minBpsToSeller,
    order.nonce
  ];
  const constraintsHash = keccak256(
    defaultAbiCoder.encode(['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256'], constraints)
  );

  let encodedItems = '';
  for (const item of order.nfts) {
    const collection = item.collection;
    const tokens = item.tokens;
    let encodedTokens = '';
    for (const token of tokens) {
      encodedTokens += defaultAbiCoder.encode(['uint256', 'uint256'], [token.tokenId, token.numTokens]);
    }
    const encodedTokensHash = keccak256(encodedTokens);
    encodedItems += defaultAbiCoder.encode(['address', 'bytes32'], [collection, encodedTokensHash]);
  }
  const encodedItemsHash = keccak256(encodedItems);

  const execParams = [order.execParams.complicationAddress, order.execParams.currencyAddress];
  const execParamsHash = keccak256(defaultAbiCoder.encode(['address', 'address'], execParams));

  const dataHash = keccak256(
    defaultAbiCoder.encode(['bytes32', 'bytes32', 'bytes32'], [constraintsHash, encodedItemsHash, execParamsHash])
  );

  const extraParams = defaultAbiCoder.encode(['address'], [order.extraParams.buyer ?? NULL_ADDRESS]);

  // sign order
  const sig = await signOBOrder(chainId, contractAddress, order.isSellOrder, signer, dataHash, extraParams);
  const signedOrder: SignedOBOrder = {
    isSellOrder: order.isSellOrder,
    signer: order.signerAddress,
    dataHash,
    extraParams,
    nfts: order.nfts,
    constraints,
    execParams,
    sig
  };

  // return
  return signedOrder;
}

export async function signOBOrder(
  chainId: BigNumberish,
  contractAddress: string,
  isSellOrder: boolean,
  signer: JsonRpcSigner,
  dataHash: BytesLike,
  extraParams: BytesLike
): Promise<string> {
  const domain = {
    name: 'InfinityExchange',
    version: '1',
    chainId: chainId,
    verifyingContract: contractAddress
  };

  const types = {
    Order: [
      { name: 'isSellOrder', type: 'bool' },
      { name: 'signer', type: 'address' },
      { name: 'dataHash', type: 'bytes32' },
      { name: 'extraParams', type: 'bytes' }
    ]
  };

  const orderToSign = {
    isSellOrder,
    signer: await signer.getAddress(),
    dataHash,
    extraParams
  };

  // sign order
  try {
    console.log('Signing order');
    const sig = await signer._signTypedData(domain, types, orderToSign);
    const splitSig = splitSignature(sig ?? '');
    const encodedSig = defaultAbiCoder.encode(['bytes32', 'bytes32', 'uint8'], [splitSig.r, splitSig.s, splitSig.v]);
    return encodedSig;
  } catch (e) {
    console.error('Error signing order', e);
  }

  return '';
}
