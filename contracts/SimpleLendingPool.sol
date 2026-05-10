// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleLendingPool
 * @notice Lending Pool đơn giản cho Arc Testnet
 *         - Gửi USDC để kiếm lãi (APY cố định)
 *         - Vay USDC bằng cách thế chấp ETH (overcollateralized)
 *         - Repay khoản vay + lãi
 */
contract SimpleLendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────
    uint256 public constant BORROW_RATE_PER_YEAR = 800;   // 8% APY
    uint256 public constant SUPPLY_RATE_PER_YEAR = 500;   // 5% APY
    uint256 public constant COLLATERAL_RATIO     = 150;   // 150% collateral required
    uint256 public constant LIQUIDATION_THRESHOLD= 120;   // liquidate if < 120%
    uint256 public constant BASIS_POINTS         = 10_000;
    uint256 public constant SECONDS_PER_YEAR     = 365 days;

    // ─── State ───────────────────────────────────────────────
    IERC20 public immutable usdc;

    struct SupplyPosition {
        uint256 amount;         // USDC gửi vào
        uint256 lastUpdated;    // timestamp cập nhật lần cuối
        uint256 accruedInterest;// lãi tích lũy
    }

    struct BorrowPosition {
        uint256 borrowed;       // USDC đã vay
        uint256 collateral;     // ETH thế chấp (wei)
        uint256 lastUpdated;
        uint256 accruedInterest;
    }

    mapping(address => SupplyPosition) public supplies;
    mapping(address => BorrowPosition) public borrows;

    uint256 public totalSupplied;
    uint256 public totalBorrowed;

    // ─── Events ──────────────────────────────────────────────
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 interest);
    event Borrowed(address indexed user, uint256 amount, uint256 collateral);
    event Repaid(address indexed user, uint256 amount, uint256 interest);
    event Liquidated(address indexed user, address liquidator, uint256 debtRepaid);

    // ─── Mock price (testnet only) ────────────────────────────
    // Giá ETH/USDC giả định: 2000 USDC/ETH (testnet demo)
    uint256 public ethPriceUSDC = 2000e6; // 2000 USDC với 6 decimals

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
    }

    // ──────────────────────────────────────────────────────────
    // SUPPLY (GỬI TIỀN)
    // ──────────────────────────────────────────────────────────

    /**
     * @notice Gửi USDC vào pool để kiếm lãi 5%/năm
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        _accrueSupplyInterest(msg.sender);

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        supplies[msg.sender].amount += amount;
        totalSupplied += amount;

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Rút USDC + lãi tích lũy
     */
    function withdraw(uint256 amount) external nonReentrant {
        _accrueSupplyInterest(msg.sender);

        SupplyPosition storage pos = supplies[msg.sender];
        uint256 totalBalance = pos.amount + pos.accruedInterest;
        require(amount <= totalBalance, "Insufficient balance");
        require(availableLiquidity() >= amount, "Not enough liquidity in pool");

        uint256 interestPaid = 0;
        if (amount <= pos.accruedInterest) {
            pos.accruedInterest -= amount;
        } else {
            interestPaid = pos.accruedInterest;
            uint256 principalWithdrawn = amount - pos.accruedInterest;
            pos.accruedInterest = 0;
            pos.amount -= principalWithdrawn;
            totalSupplied -= principalWithdrawn;
        }

        usdc.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, interestPaid);
    }

    // ──────────────────────────────────────────────────────────
    // BORROW (VAY TIỀN)
    // ──────────────────────────────────────────────────────────

    /**
     * @notice Vay USDC, cần thế chấp ETH (150% giá trị khoản vay)
     */
    function borrow(uint256 usdcAmount) external payable nonReentrant {
        require(usdcAmount > 0, "Amount must be > 0");
        require(availableLiquidity() >= usdcAmount, "Not enough liquidity");

        // Tính ETH cần thế chấp:
        // usdcAmount (6 decimals) * 150/100 / ethPriceUSDC (6 decimals) * 1e18
        // = usdcAmount * 150 * 1e18 / (100 * ethPriceUSDC)
        uint256 requiredCollateral = (usdcAmount * COLLATERAL_RATIO * 1e18)
            / (100 * ethPriceUSDC);

        require(msg.value >= requiredCollateral, "Insufficient collateral");

        _accrueBorrowInterest(msg.sender);

        borrows[msg.sender].borrowed += usdcAmount;
        borrows[msg.sender].collateral += msg.value;
        borrows[msg.sender].lastUpdated = block.timestamp;
        totalBorrowed += usdcAmount;

        usdc.safeTransfer(msg.sender, usdcAmount);
        emit Borrowed(msg.sender, usdcAmount, msg.value);
    }

    /**
     * @notice Trả khoản vay + lãi 8%/năm
     */
    function repay(uint256 amount) external nonReentrant {
        _accrueBorrowInterest(msg.sender);

        BorrowPosition storage pos = borrows[msg.sender];
        uint256 totalDebt = pos.borrowed + pos.accruedInterest;
        require(totalDebt > 0, "No debt to repay");

        uint256 repayAmount = amount > totalDebt ? totalDebt : amount;
        usdc.safeTransferFrom(msg.sender, address(this), repayAmount);

        uint256 interestPaid = 0;
        if (repayAmount <= pos.accruedInterest) {
            pos.accruedInterest -= repayAmount;
        } else {
            interestPaid = pos.accruedInterest;
            uint256 principalRepaid = repayAmount - pos.accruedInterest;
            pos.accruedInterest = 0;
            pos.borrowed -= principalRepaid;
            totalBorrowed -= principalRepaid;
        }

        // Hoàn trả ETH theo tỷ lệ nếu trả hết
        if (pos.borrowed == 0 && pos.accruedInterest == 0 && pos.collateral > 0) {
            uint256 collateralToReturn = pos.collateral;
            pos.collateral = 0;
            (bool ok,) = payable(msg.sender).call{value: collateralToReturn}("");
            require(ok, "ETH transfer failed");
        }

        emit Repaid(msg.sender, repayAmount, interestPaid);
    }

    /**
     * @notice Thanh lý vị thế nếu tỷ lệ thế chấp < 120%
     */
    function liquidate(address borrower) external nonReentrant {
        _accrueBorrowInterest(borrower);

        BorrowPosition storage pos = borrows[borrower];
        require(pos.borrowed > 0, "No active borrow");

        uint256 collateralValueUSDC = (pos.collateral * ethPriceUSDC) / 1e18;
        uint256 totalDebt = pos.borrowed + pos.accruedInterest;
        uint256 currentRatio = (collateralValueUSDC * 100) / totalDebt;

        require(currentRatio < LIQUIDATION_THRESHOLD, "Position is healthy");

        // Liquidator trả hết nợ, nhận toàn bộ collateral
        usdc.safeTransferFrom(msg.sender, address(this), totalDebt);
        totalBorrowed -= pos.borrowed;

        uint256 collateralToSend = pos.collateral;
        pos.borrowed = 0;
        pos.accruedInterest = 0;
        pos.collateral = 0;

        payable(msg.sender).transfer(collateralToSend);
        emit Liquidated(borrower, msg.sender, totalDebt);
    }

    // ──────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ──────────────────────────────────────────────────────────

    function getSupplyBalance(address user) external view returns (
        uint256 principal,
        uint256 interest,
        uint256 total
    ) {
        SupplyPosition memory pos = supplies[user];
        uint256 newInterest = _calculateInterest(
            pos.amount, SUPPLY_RATE_PER_YEAR, pos.lastUpdated
        );
        principal = pos.amount;
        interest  = pos.accruedInterest + newInterest;
        total     = principal + interest;
    }

    function getBorrowBalance(address user) external view returns (
        uint256 debt,
        uint256 interest,
        uint256 total,
        uint256 collateral,
        uint256 healthFactor
    ) {
        BorrowPosition memory pos = borrows[user];
        uint256 newInterest = _calculateInterest(
            pos.borrowed, BORROW_RATE_PER_YEAR, pos.lastUpdated
        );
        debt       = pos.borrowed;
        interest   = pos.accruedInterest + newInterest;
        total      = debt + interest;
        collateral = pos.collateral;

        if (total > 0) {
            uint256 collateralValueUSDC = (pos.collateral * ethPriceUSDC) / 1e18;
            healthFactor = (collateralValueUSDC * 100) / total;
        }
    }

    function availableLiquidity() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function poolStats() external view returns (
        uint256 supplied,
        uint256 borrowed,
        uint256 liquidity,
        uint256 utilizationRate
    ) {
        supplied      = totalSupplied;
        borrowed      = totalBorrowed;
        liquidity     = availableLiquidity();
        utilizationRate = totalSupplied > 0
            ? (totalBorrowed * BASIS_POINTS) / totalSupplied
            : 0;
    }

    // ──────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ──────────────────────────────────────────────────────────

    function _calculateInterest(
        uint256 principal,
        uint256 ratePerYear,
        uint256 lastUpdated
    ) internal view returns (uint256) {
        if (principal == 0 || lastUpdated == 0) return 0;
        uint256 elapsed = block.timestamp - lastUpdated;
        return (principal * ratePerYear * elapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);
    }

    function _accrueSupplyInterest(address user) internal {
        SupplyPosition storage pos = supplies[user];
        if (pos.lastUpdated > 0) {
            pos.accruedInterest += _calculateInterest(
                pos.amount, SUPPLY_RATE_PER_YEAR, pos.lastUpdated
            );
        }
        pos.lastUpdated = block.timestamp;
    }

    function _accrueBorrowInterest(address user) internal {
        BorrowPosition storage pos = borrows[user];
        if (pos.lastUpdated > 0) {
            pos.accruedInterest += _calculateInterest(
                pos.borrowed, BORROW_RATE_PER_YEAR, pos.lastUpdated
            );
        }
        pos.lastUpdated = block.timestamp;
    }

    // Owner có thể cập nhật giá ETH (testnet only)
    function setEthPrice(uint256 newPrice) external onlyOwner {
        ethPriceUSDC = newPrice;
    }

    receive() external payable {}
}
