import { ethers } from 'hardhat';
import console from 'console';

// const _metadataUri = 'https://gateway.pinata.cloud/ipfs/https://gateway.pinata.cloud/ipfs/QmX2ubhtBPtYw75Wrpv6HLb1fhbJqxrnbhDo1RViW3oVoi';

async function deploy(name: string, ...params: [string?]) {
  const contractFactory = await ethers.getContractFactory(name);

  return await contractFactory.deploy(...params);
}

async function main() {
  // const [owner] = await ethers.getSigners();
  
  console.log(`Deploying a smart contract...`);

  const contract = (await deploy('MysteryChineseChess'));//.connect(owner);

  console.log({ addr: await contract.getAddress() });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  });
