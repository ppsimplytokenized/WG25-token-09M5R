# Universal Token

UniversalToken is an upgradeable ERC-20 token built with OpenZeppelin libraries. It adds
role-based minting & burning, pausing, seizure, and a **time-limited blocklist** on top of a
standard ERC-20, making it suitable for regulated/compliance-sensitive assets that require
fine-grained control over transferability.

## ✨ Features

- ✅ ERC-20 compliant with configurable decimals
- 🔒 Role-based access control (mint, burn, pause, freeze)
- 🔥 Burnable — **restricted to authorized roles** (see [Burn semantics](#-burn-semantics))
- ⏸️ Pausable transfers
- 🚫 Blocklisting with **per-account expiry dates** (temporary or permanent)
- 🧨 Seizure of blocked funds via `forceBurn` (works even while paused)
- 🧾 Permit (EIP-2612) support for gasless approvals
- 🧬 Fully upgradeable (OpenZeppelin transparent proxy pattern)

## 🔐 Roles

| Role                 | Capabilities                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Grants/revokes all other roles                                      |
| `MINTER_ROLE`        | Mint (uncapped), `burn`, and `burnFrom`                             |
| `PAUSER_ROLE`        | Pause / unpause transfers                                           |
| `FREEZER_ROLE`       | Block / unblock users and `forceBurn` (seize) blocked balances      |

> ⚠️ These roles are trust-critical. In production, assign them to multisigs/timelocks — a
> single `MINTER_ROLE` key can mint unlimited supply, and a single `FREEZER_ROLE` key can
> block any account and destroy its balance via `forceBurn`.

## 🚫 Blocklist

A blocked account cannot **send**, **receive**, or be granted a **new (non-zero) allowance**,
and cannot act as the **spender** in a `transferFrom`. Blocks carry an expiry date and lift
automatically when it passes — no unblock transaction required.

| Function                              | Effect                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `blockUser(user, blockedUntil)`       | Block until a Unix timestamp (a date); auto-unblocks after it. Reverts if the date is not in the future. |
| `blockUserPermanent(user)`            | Block indefinitely (never auto-expires)                                |
| `unblockUser(user)`                   | Unblock immediately, before any scheduled expiry                       |
| `blocked(user) → bool`                | Current status (`block.timestamp < blockedUntil`)                      |
| `blockedUntil(user) → uint256`        | The expiry timestamp (`0` if not blocked, `type(uint256).max` if permanent) |

Notes:

- Calling `blockUser` again **overwrites** the expiry (extend or shorten a block).
- The **zero address can never be blocked** — this is enforced so minting and burning can never be bricked.
- **`forceBurn(account, amount)`** (FREEZER-only) destroys tokens held by a currently-blocked
  account. It works even while the contract is paused (for incident response), and reverts if
  the account is not blocked. Because it burns rather than transfers, no funds move to another address.

## 🔥 Burn semantics

Unlike the standard `ERC20Burnable`, `burn` and `burnFrom` are **restricted to `MINTER_ROLE`** —
ordinary holders **cannot** burn their own tokens. This is deliberate for a controlled/regulated
asset, but is a deviation from the ERC-20 burnable standard that integrators (DEXes, bridges,
yield protocols) should be aware of.

## 🧬 Upgradeability & upgrade authority

The token sits behind an OpenZeppelin `TransparentUpgradeableProxy`. The **owner of the
`ProxyAdmin`** — set at deployment via `PROXY_ADMIN_OWNER` — controls upgrades and is the single
most powerful privilege in the system (it can replace the implementation entirely, bypassing all
roles). **Set it to a multisig/timelock**, not the deployer EOA. If `PROXY_ADMIN_OWNER` is unset,
it falls back to the deployer (acceptable only for local/testnet use).

## 🚀 Deployment

### Initialization parameters

| Parameter       | Description                         |
|-----------------|-------------------------------------|
| `tokenName`     | The name of the token               |
| `tokenSymbol`   | The symbol (e.g., `UT`)             |
| `tokenDecimals` | Number of decimal places (e.g., 8)  |

```solidity
UniversalToken.initialize("Universal Token", "UT", 8);
```

### Environment

Copy `.env.sample` to `.env` and fill in the values. Key entries:

| Variable            | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `TOKEN_NAME` / `TOKEN_SYMBOL` / `TOKEN_DECIMALS` | Initialization parameters                  |
| `PROXY_ADMIN_OWNER` | Owner of the ProxyAdmin (upgrade authority). Set to a multisig for production; falls back to the deployer if unset. |

### Foundry deployment

Note: when deploying with some setups (e.g. Ledger), Foundry may use a default value for the
sender, which would set the ProxyAdmin owner to that default and prevent later upgrades.
Therefore `--sender <0xOwnerAddress>` is used in the sample commands below:

```bash
source .env
# Deploy to Ethereum Sepolia using keystores and custom optimizer-runs + verify contract
forge script script/DeployToken.s.sol:DeployToken --keystore keystores/deployer --broadcast --slow --verify --rpc-url $ETH_SEPOLIA_RPC --etherscan-api-key $ETHERSCAN_API_KEY --sender $DEPLOYER  --optimizer-runs 10000

# Deploy to Avalanche Fuji with private key + verify contracts
forge script script/DeployToken.s.sol:DeployToken --private-key $DEPLOYER_KEY --broadcast --optimize --slow --verify --rpc-url $AVALANCHE_FUJI_RPC --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url $AVALANCHE_FUJI_VERIFIER_URL --sender $DEPLOYER
```

## 🧪 Foundry commands

```bash
# build
forge build

# run tests (unit, fuzz, invariant, upgrade-path)
forge test

# coverage (build first so the upgrades plugin can resolve artifacts)
forge build && forge coverage

# format code
forge fmt

# gas report
forge test --gas-report --optimizer-runs 10000

# static analysis
slither .
```

## 🔒 Security

The contract has undergone internal review and ships with unit, fuzz, invariant, and
upgrade-path tests (100% line/branch/function coverage on the custom contracts). Role keys are
trust-critical — use multisigs for `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `FREEZER_ROLE`, and the
`ProxyAdmin` owner. An **independent third-party audit** is recommended before any mainnet
deployment carrying real value.
