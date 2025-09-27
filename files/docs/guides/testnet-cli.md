# Ephemeral Testnet Quickstart

This guide shows how to experiment with the in-memory testnet node. It is safe to run on any machine: **no files are written and all blockchain data disappears when you exit**.

## 1. Launch the CLI

```bash
julia --startup-file=no aequchain.jl cli
```

You will see the `aequchain >` prompt. The CLI uses a soft color palette—commands appear in white and hints in grey.

## 2. Bootstrap a Fresh Node

```text
node_init 16 11
```

- **16**: maximum committee size selected for each block.
- **11**: quorum threshold (minimum votes required). The CLI prevents thresholds greater than the committee size.
- Every run starts empty: zero accounts, zero blocks, zero persistence.

## 3. Register Members (Free Admission)

```text
node_register alice 1000
node_register bob 800
```

- Balances are whole-number integers (`UInt128` internally).
- You can re-run `node_register` with new IDs as much as you like. Each account gets a token-bucket rate limiter to prevent spam while remaining free to join.

## 4. Send a Payment

```text
node_pay alice bob 125
```

What happens behind the scenes:

1. The node builds a send block (`alice → bob`, amount = 125) and a receive block (`bob ← alice`).
2. Deterministic committee selection samples 16 members (or fewer if you registered fewer accounts).
3. Each block gathers votes and forms a quorum certificate (QC) using canonical SHA-256 JSON hashes.
4. Metrics are recorded—latency (ms), throughput (tx/s), uptime, and memory estimates.
5. A summary screen appears with block hashes, vote tallies, and the latest metrics.

If a sender or recipient is missing, the CLI prints a grey hint: register the absent account and retry. No funds are ever lost—the ledger stays perfectly equal.

## 5. Inspect Status & Metrics

```text
node_status
```

Displays:

- Accounts, blocks, and quorum certificates produced so far.
- Account balances (first 10 entries) to double-check who is available.
- Live metrics: total payments, throughput, average/last latency, uptime, and memory usage.
- Headroom projections for 4 GB and 8 GB RAM—use these to estimate how many additional payments you can simulate before hitting your limit.

For a deeper report (or custom memory target):

```text
node_metrics 12
```

Adds projections for 12 GB while keeping the standard 4 GB and 8 GB outputs.

## 6. Explore Blocks and QCs

```text
node_blocks 3
node_qc 3
```

- `node_blocks` prints the latest canonical JSON blocks. Each entry is deterministic—hashes match across machines.
- `node_qc` shows quorum certificates, including vote bitmaps and thresholds.

## 7. Reset Anytime

```text
node_reset
```

Discards all in-memory data. Combine with `node_init` to start another experiment.

## Troubleshooting Cheatsheet

| Symptom | Fix |
| --- | --- |
| `node_pay failed: Unknown sender X` | Register the sender: `node_register X <balance>` |
| `node_pay failed: Unknown recipient Y` | Register the recipient before sending |
| Throughput shows `0.00 tx/s` | Send at least one payment; metrics update after each transaction |
| Need more accounts on screen | Run `node_balance` (all accounts) or `node_status` (first 10) |
| Want to cap RAM usage | Start your shell session with `ulimit -Sv <kilobytes>` before launching Julia |

## Recording Experiments

While the node is ephemeral, you can still log results:

1. Run commands in the CLI.
2. Copy the metrics displayed after `node_pay`, `node_status`, or `node_metrics`.
3. Paste them into your own notebook or spreadsheet for tracking.

The combination of canonical hashes and deterministic committee selection makes results reproducible. Restart the CLI, reuse the same sequence, and you will see the identical block JSON and QCs.

---

**Remember:** close the CLI window or press `Ctrl + C` to exit—the blockchain state disappears immediately, keeping the environment clean and safe.
