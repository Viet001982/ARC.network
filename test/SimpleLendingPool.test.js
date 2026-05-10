const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleLendingPool", function () {
  let pool, usdc, owner, alice, bob;
  const USDC_DECIMALS = 6;
  const toUSDC = (n) => ethers.parseUnits(String(n), USDC_DECIMALS);

  beforeEach(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy mock USDC (ERC20)
    const MockERC20 = await ethers.getContractFactory("MockUSDC");
    usdc = await MockERC20.deploy();

    // Deploy lending pool
    const Pool = await ethers.getContractFactory("SimpleLendingPool");
    pool = await Pool.deploy(await usdc.getAddress());

    // Mint USDC cho alice và bob để test
    await usdc.mint(alice.address, toUSDC(10_000));
    await usdc.mint(bob.address, toUSDC(5_000));

    // Approve pool để dùng USDC
    await usdc.connect(alice).approve(await pool.getAddress(), ethers.MaxUint256);
    await usdc.connect(bob).approve(await pool.getAddress(), ethers.MaxUint256);
  });

  // ─── Deposit Tests ────────────────────────────────────────
  describe("deposit()", () => {
    it("should accept USDC deposits", async () => {
      await pool.connect(alice).deposit(toUSDC(1000));
      const [principal] = await pool.getSupplyBalance(alice.address);
      expect(principal).to.equal(toUSDC(1000));
    });

    it("should update totalSupplied", async () => {
      await pool.connect(alice).deposit(toUSDC(1000));
      const stats = await pool.poolStats();
      expect(stats.supplied).to.equal(toUSDC(1000));
    });

    it("should reject zero deposit", async () => {
      await expect(pool.connect(alice).deposit(0))
        .to.be.revertedWith("Amount must be > 0");
    });
  });

  // ─── Withdraw Tests ───────────────────────────────────────
  describe("withdraw()", () => {
    it("should allow withdrawal of principal", async () => {
      await pool.connect(alice).deposit(toUSDC(1000));
      const balanceBefore = await usdc.balanceOf(alice.address);

      await pool.connect(alice).withdraw(toUSDC(500));

      const balanceAfter = await usdc.balanceOf(alice.address);
      expect(balanceAfter - balanceBefore).to.equal(toUSDC(500));
    });

    it("should reject withdrawal exceeding balance", async () => {
      await pool.connect(alice).deposit(toUSDC(1000));
      await expect(pool.connect(alice).withdraw(toUSDC(2000)))
        .to.be.revertedWith("Insufficient balance");
    });
  });

  // ─── Borrow Tests ─────────────────────────────────────────
  describe("borrow()", () => {
    beforeEach(async () => {
      // Alice cung cấp thanh khoản
      await pool.connect(alice).deposit(toUSDC(5000));
    });

    it("should allow borrowing with sufficient collateral", async () => {
      // Vay 1000 USDC, cần ETH thế chấp 150%
      // 1000 USDC * 150% / 2000 (ETH price) = 0.75 ETH
      const borrowAmount = toUSDC(1000);
      const collateral = ethers.parseEther("0.75");

      await pool.connect(bob).borrow(borrowAmount, { value: collateral });

      const [debt] = await pool.getBorrowBalance(bob.address);
      expect(debt).to.equal(borrowAmount);
    });

    it("should reject borrow with insufficient collateral", async () => {
      const borrowAmount = toUSDC(1000);
      const insufficientCollateral = ethers.parseEther("0.1"); // quá ít

      await expect(
        pool.connect(bob).borrow(borrowAmount, { value: insufficientCollateral })
      ).to.be.revertedWith("Insufficient collateral");
    });
  });

  // ─── Repay Tests ──────────────────────────────────────────
  describe("repay()", () => {
    it("should allow loan repayment and return collateral", async () => {
      await pool.connect(alice).deposit(toUSDC(5000));

      const borrowAmount = toUSDC(1000);
      const collateral = ethers.parseEther("0.75");
      await pool.connect(bob).borrow(borrowAmount, { value: collateral });

      // Mint thêm USDC cho bob để đảm bảo đủ trả lãi
      await usdc.mint(bob.address, toUSDC(100));
      await usdc.connect(bob).approve(await pool.getAddress(), ethers.MaxUint256);

      // Repay toàn bộ (MaxUint256 = trả hết)
      await pool.connect(bob).repay(ethers.MaxUint256);

      const [,,, collateralAfter] = await pool.getBorrowBalance(bob.address);
      expect(collateralAfter).to.equal(0);
    });
  });

  // ─── Pool Stats ───────────────────────────────────────────
  describe("poolStats()", () => {
    it("should track utilization rate correctly", async () => {
      await pool.connect(alice).deposit(toUSDC(2000));
      await pool.connect(bob).borrow(toUSDC(1000), {
        value: ethers.parseEther("0.75"),
      });

      const stats = await pool.poolStats();
      // Utilization = 1000/2000 = 50% = 5000 basis points
      expect(stats.utilizationRate).to.equal(5000n);
    });
  });
});
