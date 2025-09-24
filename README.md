# aequchain

Universal Equidistributed Blockchain (demo implementation with exact arithmetic)

## Overview
- `aequchain.jl` is a compact, educational implementation of a Universal Equidistributed Blockchain (UEB).
- Focuses on mathematically exact equality, safety limits, and simple, auditable state transitions.
- Uses exact Rational arithmetic for money (`Rational{BigInt}`) to avoid rounding/drift.
- Runs entirely in-memory in demo mode. No persistence. Not production-ready.

## Key Concepts
- **Exact Equality:** Each member holds a non-transferable “member coin” whose value is always exactly treasury_value / member_count.
- **30‑Day Safety Cap:** Each person’s total 30‑day spend is capped at their current equal share. Prevents any single actor from draining the treasury.
- **Stablecoin Treasury:** Treasury holds stable coins pegged to a currency at a rational exchange rate.
- **Networks & Denominations:** Multiple networks with denominations and rational rates per stablecoin for display/accounting.
- **Businesses:** Owned by members, have a contribution rate (0–5%). Demo includes an allocation budget field for spending checks.
- **Pledges:** Member or business fundraising goals; business pledges can be flagged as recurring (simulated in demo).
- **Blockchain Log:** Minimal block chain with SHA‑256 hashes for each transaction for auditability (no consensus/peers in demo).

## What’s Implemented
- Data structures: `Treasury`, `MemberCoin`, `Member`, `Network`, `Business`, `Pledge`, `Transaction`, `Block`.
- Core flows: treasury init, member join/exit, transfers (logged, equality preserved), networks join/create, businesses create/set contribution, pledges create/support, spending with safety checks, status printing.
- Exact money math: all amounts stored as cents using `Rational{BigInt}`.

## Quick Start
Run the built‑in demo (auto-executes when the file is run as a script):

```bash
julia "aequchain.jl"
```

Or from a Julia REPL:

```julia
include("aequchain.jl")
run_demo()
```

You’ll see a sequence of transactions covering treasury initialization, members joining, network creation/joining, business configuration, pledges, and a final status snapshot. All state is in memory and cleared when the process exits.

## Programmatic Usage (Examples)
After `include("aequchain.jl")` you can call the functions directly:

```julia
init_treasury(100.0, "USD", 1.0, "founder")          # deposit, currency, rate, founder id
join_member("alice", 100.0)                           # deposit must match equal share within tolerance
join_member("bob", 100.0)

net_usd = create_network("USD_Net", "USD", 1.0, "founder")
join_network("alice", net_usd)

bus_id = create_business("EquiTech", "founder", net_usd)
set_contrib_rate(bus_id, 0.03, "founder")             # 3%

pledge_id = create_pledge("StartupBoost", 2000.0, "founder", net_usd,
						  "Additional funding", true, true, 100.0)
support_pledge(pledge_id, 60.0, "alice")

print_status()
```

Notes:
- `join_member` requires the depositor to provide exactly the current equal value (with a small tolerance). This preserves equality.
- `business_spend(bus_id, amount, purpose, owner)` respects both the owner’s 30‑day safety cap and the business allocation budget.
- For demo simplicity, `alloc_budget` starts at zero; adjust in code or extend with an allocation function if you want to experiment.

## Safety Model
- 30‑day rolling spend per member cannot exceed their equal share: `member_share = treasury_stable_coins / total_members`.
- All spends record into a member’s history and are validated before applying.
- Equality is invariant: transfers are logged but do not change anyone’s equal value.

## Demo/Design Limitations
- DEMO_MODE=true: memory‑only, no persistence, simplified behaviors.
- No cryptographic signatures or consensus; the block log is for traceability only.
- Networking is not implemented; “networks” here model denominations and membership groupings, not P2P.
- Recurring pledges are announced in logs but not scheduled tasks.

## File Layout
- `aequchain.jl` — the exact arithmetic UEB demo with data types and flows described above.
- `Universal Equality Blockchain.jl` — a separate educational script with interactive commands and documentation below.

## Disclaimer
Educational proof‑of‑concept only. Not audited. Do not use in production. Any real deployment requires robust cryptography, consensus, persistent storage, network security, and rigorous economic safety enforcement.

------------------------------
# Universal Equality Blockchain

**A basis for free and equal economy, encapsulated in blockchain and smart contract technology**

## 🔒 Important Disclaimers

### ⚠️ DEMO MODE - SAFE FOR TESTING
- **Currently set to DEMO_MODE = true** - Safe to run and exit
- **No persistent storage** - All blockchain state exists only in memory
- **No files created** - Program leaves no traces on your system
- **Educational purpose** - Designed for learning and prototyping

### 🚫 Production Warning
- **DO NOT use in production** without implementing proper ECDSA cryptography
- **Requires peer network** setup for real-world deployment
- **Simplified crypto** - Current implementation uses demo-grade security only

### 🛡️ CRITICAL SECURITY REQUIREMENT
- **ESSENTIAL SAFETY MECHANISM REQUIRED**: Any production implementation MUST enforce equal safety allocation "limits"
- **Treasury Protection**: Each user's withdrawal/transfer capacity MUST be safety capped to their proportional share of stable coins
- **Prevents Sabotage**: Without this constraint, a single malicious actor could deplete the entire treasury
- **INTEGRAL DESIGN PRINCIPLE**: Equal distribution requires equal risk limits - no user should access more funds than their peers without their consent
- **VITAL FOR SYSTEM INTEGRITY**: This is not optional - it's a foundational requirement for treasury security

### ⚖️ Liability Disclaimer
- This software is provided **"AS IS"** for educational and research purposes
- **NO LIABILITY** assumed by author/creator for any use of this software
- **Users assume full responsibility** for any implementation or deployment
- **Not financial advice** - purely a technical proof-of-concept
- **Open source** - use at your own risk and discretion

## � Understanding the Code

**Easy way to learn:** Copy and paste the code into an AI LLM (GitHub Copilot Chat, Claude, ChatGPT, etc.) and ask it to explain what it does, how it works, and walk you through the implementation.

## �🚀 Quick Start

### Prerequisites

**Cross-Platform Installation Instructions:**

#### Windows
```powershell
# Install Julia (choose one method):

# Method 1: Download from official site
# Visit: https://julialang.org/downloads/
# Download Windows installer and run

# Method 2: Using Chocolatey
choco install julia

# Method 3: Using winget
winget install julia
```

#### macOS
```bash
# Install Julia (choose one method):

# Method 1: Download from official site
# Visit: https://julialang.org/downloads/
# Download macOS installer and run

# Method 2: Using Homebrew
brew install julia

# Method 3: Using MacPorts
sudo port install julia
```

#### Linux (Ubuntu/Debian)
```bash
# Method 1: Official repository (recommended)
curl -fsSL https://install.julialang.org | sh
source ~/.bashrc

# Method 2: Package manager
sudo apt update
sudo apt install julia

# Method 3: Snap
sudo snap install julia --classic
```

#### Linux (CentOS/RHEL/Fedora)
```bash
# Fedora
sudo dnf install julia

# CentOS/RHEL (enable EPEL first)
sudo yum install epel-release
sudo yum install julia
```

#### Arch Linux
```bash
sudo pacman -S julia
```

### Verify Installation
```bash
julia --version
# Should show: julia version 1.8+ (or higher)
```

### Running the Blockchain

#### Download and Run
```bash
# Clone the repository
git clone https://github.com/ttx89-dev/Universal-Equity-Blockchain.git
cd Universal-Equity-Blockchain

# Run interactive mode
julia "Universal Equality Blockchain.jl"

# OR run automated tests
julia "Universal Equality Blockchain.jl" test
```

#### Alternative: Direct Download
```bash
# Download the single file
wget https://raw.githubusercontent.com/ttx89-dev/Universal-Equity-Blockchain/main/Universal%20Equality%20Blockchain.jl

# Run it
julia "Universal Equality Blockchain.jl"
```

## 📚 Usage Guide

### Interactive Commands
```bash
EqualityChain> help                          # Show all commands
EqualityChain> genesis founder_address       # Create genesis block  
EqualityChain> create_coins                  # Create stable coins (auto-config)
EqualityChain> join member_addr 17.27        # Join as new member
EqualityChain> status                        # Show blockchain status
EqualityChain> members                       # List all members
EqualityChain> validate                      # Validate entire chain
EqualityChain> network start 8080            # Start P2P node
EqualityChain> exit                          # Safe exit (clears memory)
```

### Example Session
```bash
julia "Universal Equality Blockchain.jl"

EqualityChain> genesis founder123
✅ Genesis block created!

EqualityChain> create_coins  
✅ Stable coins created!

EqualityChain> join member456 1.0
✅ Member joined!

EqualityChain> status
# Shows complete blockchain state

EqualityChain> exit
👋 Goodbye!
# All data cleared from memory
```

## ✨ Key Features

- ✅ **Ultra-lightweight** (< 1MB memory usage)
- ✅ **Instant feeless transactions**
- ✅ **Perfect mathematical equality** (treasury_value / member_count)
- ✅ **Every transaction validates entire chain**
- ✅ **1 node per member architecture**
- ✅ **Real currency pegging** via stable coins
- ✅ **Complete P2P networking foundation**
- ✅ **Scales from 1 person to global adoption** (< 800MB even at global scale)
- ✅ **Mobile/embedded device compatible**
- ✅ **Supports all world currencies** via stable coin pegging
- ✅ **DEMO MODE: Safe to run and exit** - no persistent storage
- ✅ **Requires peer nodes** for production network deployment
- ✅ **Mathematical proof of concept** for free and equal economy
- ✅ **Peer-to-peer stable coin transfers** with automatic rebalancing
- ✅ **Perfect equality maintained** during transactions (3 peers with 30 stable coins each remain equal after any transfer)

## 🔧 Configuration

### Launch Parameters
Edit these constants in the Julia file:

```julia
const DEMO_MODE = true                    # Keep true for safe testing
const LAUNCH_PEG_AMOUNT = 1              # Your currency input amount
const LAUNCH_STABLE_COINS = 1.0          # Stable coins to create
const LAUNCH_PEG_CURRENCY = "USD"        # Peg currency (USD, EUR, etc.)
const LAUNCH_PEG_RATE = 1                # Exchange rate
```

### Example Configurations
```julia
# 100 ZAR creating ZAR-pegged coins:
LAUNCH_PEG_AMOUNT = 100.0, LAUNCH_STABLE_COINS = 100.0, 
LAUNCH_PEG_CURRENCY = "ZAR", LAUNCH_PEG_RATE = 1.0

# 17.27 ZAR creating USD-pegged coin:  
LAUNCH_PEG_AMOUNT = 17.27, LAUNCH_STABLE_COINS = 1.0,
LAUNCH_PEG_CURRENCY = "USD", LAUNCH_PEG_RATE = 17.27
```

## 🌐 Core Concepts

### Three Token Types

1. **Digital Asset** - Represents ownership of the entire system
2. **Stable Coins** - Pegged to real-world currencies (USD, EUR, etc.)
3. **Native Coins** - Equal-value membership tokens (treasury_value / members)

### Mathematical Equality
- All members hold native coins of exactly equal value
- Treasury value divided equally among all members
- Perfect economic equality maintained automatically

### Blockchain Architecture
- Every transaction creates a new block
- Every block validates the entire chain
- Immutable history with cryptographic linking
- Real-time consistency validation

## 🔬 Technical Details

### Memory Usage
- **Local testing**: < 1MB for small networks
- **Global scale**: < 800MB even with worldwide adoption
- **Embedded compatible**: Runs on IoT devices and mobile

### Network Architecture
- **1 node per member** - democratic participation
- **P2P networking** - no central servers required
- **Peer discovery** - automatic network formation
- **Broadcast validation** - consensus through validation

### Cryptography (DEMO MODE)
- **Key generation**: Simplified for demo safety
- **Transaction signing**: SHA-256 based (demo only)
- **Production ready**: Framework for ECDSA implementation

## 📋 System Requirements

### Minimum
- **RAM**: 100MB available memory
- **CPU**: Any modern processor (ARM/x86/x64)
- **Storage**: No persistent storage required in demo mode
- **Network**: Optional (for P2P features)

### Recommended
- **RAM**: 1GB+ for large networks
- **CPU**: Multi-core for P2P networking
- **Network**: Stable internet for production deployment

## 🔐 Security Features

### DEMO Mode Safety
- No persistent files created
- Memory-only operation
- Safe to interrupt/exit at any time
- No system modifications

### Production Considerations
- Implement proper ECDSA key generation
- Add secure random number generation
- Deploy peer network infrastructure
- Add TLS/encryption for network communication

## 🤝 Contributing

This is an open-source educational project. Contributions welcome for:

- Production cryptography implementation
- Enhanced P2P networking
- Mobile/embedded optimizations
- Additional currency integrations
- Documentation improvements

## 📄 License

Open source - use at your own discretion and risk.

## 🌟 Vision

This blockchain represents a complete technical foundation for implementing true economic equality through mathematical guarantee rather than policy. Every member automatically receives exactly equal value, creating a basis for a free and equal economy powered by blockchain and smart contract technology.

**"A basis for free and equal economy, encapsulated in blockchain and smart contract technology"**

---

**Remember**: Currently in DEMO MODE for safe testing. No liability assumed. Educational and research purposes only.
