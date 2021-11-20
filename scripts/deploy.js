const ethers = hre.ethers;
// run the command below from the terminal to call this script
// npx hardhat run --network localhost scripts/deploy.js
async function main() {
  const contract = await ethers.getContractFactory('Contract.sol');
  const contractInstance = await contract.deploy();

  console.log('Contract deployed to:', contractInstance.address);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
