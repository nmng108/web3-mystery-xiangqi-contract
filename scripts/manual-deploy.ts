import {ethers} from "ethers";
import fs from "fs";
import * as process from "node:process";
import "dotenv";
import dotenv from "dotenv";

dotenv.config();

// "Manual" deployment using solc.js & ethers.js instead of utilizing hardhat
const RPC_SERVER_URL: string = "http://127.0.0.1:7545";
const PRIVATE_KEY: string = process.env.PRIVATE_KEY || "";

async function main() {
    const provider: ethers.JsonRpcProvider = new ethers.JsonRpcProvider(RPC_SERVER_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    // use "solc..." command or "hardhat compile"
    const abi = fs.readFileSync("./contracts/Lock_sol_Lock.abi", "utf-8");
    const bin = fs.readFileSync("./contracts/Lock_sol_Lock.bin", "utf-8");
    const contractFactory = new ethers.ContractFactory(abi, bin, wallet);

    console.log("Deploying lock contract");

    const contract = await contractFactory.deploy(Date.now());

    console.log(contract);

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
