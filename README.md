# Arc Lending DApp 🏦

DApp lending pool đơn giản xây trên **Arc Testnet** — cho phép gửi USDC kiếm lãi và vay USDC bằng cách thế chấp ETH.

## Tính năng

| Tính năng | Chi tiết |
|---|---|
| Deposit | Gửi USDC, kiếm **5% APY** |
| Withdraw | Rút vốn + lãi tích lũy |
| Borrow | Vay USDC, thế chấp ETH 150% |
| Repay | Trả nợ + lãi **8% APY** |
| Liquidate | Thanh lý khi health factor < 120% |

## Cài đặt

```bash
npm install
```

## Cấu hình

Tạo file `.env`:
```
PRIVATE_KEY=your_metamask_private_key
```

## Chạy test (local)

```bash
npx hardhat test
```

## Deploy lên Arc Testnet

```bash
npx hardhat run scripts/deploy.js --network arcTestnet
```

## Tương tác với contract

```bash
npx hardhat run scripts/interact.js --network arcTestnet
```

## Thông tin Arc Testnet

| Thông tin | Giá trị |
|---|---|
| RPC URL | `https://rpc.testnet.arc.network` |
| Chain ID | `5042002` |
| Gas token | USDC |
| Explorer | https://testnet.arcscan.app |
| Faucet | https://faucet.circle.com |

## Cấu trúc project

```
arc-lending-dapp/
├── contracts/
│   ├── SimpleLendingPool.sol   ← Contract chính
│   └── MockUSDC.sol            ← Mock USDC cho test
├── scripts/
│   ├── deploy.js               ← Deploy lên Arc
│   └── interact.js             ← Gọi các hàm sau deploy
├── test/
│   └── SimpleLendingPool.test.js
├── hardhat.config.js
└── .env                        ← Không commit lên git!
```
