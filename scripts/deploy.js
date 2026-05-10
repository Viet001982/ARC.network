const hre = require("hardhat");

// Địa chỉ USDC trên Arc Testnet (lấy từ docs.arc.network/arc/references/contract-addresses)
const USDC_ARC_TESTNET = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("  Deploying SimpleLendingPool to Arc Testnet");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("Deployer:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("USDC Balance (gas):", hre.ethers.formatUnits(balance, 18), "USDC\n");

  // Deploy contract
  const LendingPool = await hre.ethers.getContractFactory("SimpleLendingPool");
  const pool = await LendingPool.deploy(USDC_ARC_TESTNET);
  await pool.waitForDeployment();

  const address = await pool.getAddress();

  console.log("✓ SimpleLendingPool deployed!");
  console.log("  Contract address:", address);
  console.log("  USDC token:      ", USDC_ARC_TESTNET);
  console.log("\n🔍 View on explorer:");
  console.log("  https://testnet.arcscan.app/address/" + address);
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  // Lưu address vào file để dùng sau
  const fs = require("fs");
  const deployInfo = {
    network: "arcTestnet",
    contractAddress: address,
    usdcAddress: USDC_ARC_TESTNET,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
  };
  fs.writeFileSync("deployment.json", JSON.stringify(deployInfo, null, 2));
  console.log("\n✓ Saved deployment info to deployment.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
