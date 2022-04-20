import { Contract, ContractFactory, Signer, Wallet } from 'ethers';

export async function deployContract(
  name: string,
  factory: ContractFactory,
  signer: Signer,
  args: Array<any> = []
): Promise<Contract> {
  const contract = await factory.connect(signer).deploy(...args);
  // console.log('Deploying', name, 'on', await signer.provider?.getNetwork());
  // console.log('  to', contract.address);
  // console.log('  in', contract.deployTransaction.hash);
  return contract.deployed();
}
