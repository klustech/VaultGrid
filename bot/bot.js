require("dotenv").config();
const { ethers } = require("ethers");
const fs = require("fs");

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const config = JSON.parse(fs.readFileSync("./config.json"));

async function getPrice() {
  // simple placeholder price (replace later with oracle)
  return Math.random() * 4000;
}

async function run() {
  const price = await getPrice();
  console.log("Price:", price);

  if (config.dryRun) {
    console.log("Dry run mode");
    return;
  }

  if (price < config.buyBelow) {
    console.log("BUY condition met");
  }

  if (price > config.sellAbove) {
    console.log("SELL condition met");
  }
}

setInterval(run, 15000);
