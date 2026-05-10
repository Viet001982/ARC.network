/**
 * interact.js — Gọi các hàm của SimpleLendingPool sau khi deploy
 * Usage: npx hardhat run scripts/interact.js --network arcTestnet
 */
const hre = require("hardhat");
const fs = require("fs");

async function main() {
  // Đọc địa chỉ contract từ file deploy
  if (!fs.existsSync("deployment.json")) {
    throw new Error("deployment.json not found. Run deploy.js first!");
  }
  const { contractAddress, usdcAddress } = JSON.parse(
    fs.readFileSync("deployment.json", "utf8")
  );

  const [signer] = await hre.ethers.getSigners();
  console.log("Wallet:", signer.address);

  // Kết nối contract
  const pool = await hre.ethers.getContractAt("SimpleLendingPool", contractAddress);
  const usdc = await hre.ethers.getContractAt(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
    usdcAddress
  );

  // ── Kiểm tra số dư ──────────────────────────────────────────
  const usdcBalance = await usdc.balanceOf(signer.address);
  console.log("\nUSDC balance:", hre.ethers.formatUnits(usdcBalance, 6), "USDC");

  // ── Pool stats ──────────────────────────────────────────────
  const stats = await pool.poolStats();
  console.log("\n--- Pool Stats ---");
  console.log("Total supplied:   ", hre.ethers.formatUnits(stats.supplied, 6), "USDC");
  console.log("Total borrowed:   ", hre.ethers.formatUnits(stats.borrowed, 6), "USDC");
  console.log("Available liquidity:", hre.ethers.formatUnits(stats.liquidity, 6), "USDC");
  console.log("Utilization rate:", Number(stats.utilizationRate) / 100, "%");

  // ── Deposit 100 USDC ────────────────────────────────────────
  const depositAmount = hre.ethers.parseUnits("100", 6);
  console.log("\n--- Depositing 100 USDC ---");
  const approveTx = await usdc.approve(contractAddress, depositAmount);
  await approveTx.wait();
  console.log("✓ Approved");

  const depositTx = await pool.deposit(depositAmount);
  await depositTx.wait();
  console.log("✓ Deposited 100 USDC");

  // ── Kiểm tra balance của mình ──────────────────────────────
  const [principal, interest, total] = await pool.getSupplyBalance(signer.address);
  console.log("\n--- My Supply Position ---");
  console.log("Principal:", hre.ethers.formatUnits(principal, 6), "USDC");
  console.log("Interest: ", hre.ethers.formatUnits(interest, 6), "USDC");
  console.log("Total:    ", hre.ethers.formatUnits(total, 6), "USDC");

  console.log("\n🔍 View on explorer:");
  console.log("  https://testnet.arcscan.app/address/" + contractAddress);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
