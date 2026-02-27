# ERC-8004 Substreams

High-performance Substreams indexer for [ERC-8004 Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004) on **Base**.

![ERC-8004](erc8004.jpeg)

## Contracts Indexed

| Contract | Address | Events |
|----------|---------|--------|
| **IdentityRegistry** | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` | Registered, Transfer, MetadataSet, URIUpdated |
| **ReputationRegistry** | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` | NewFeedback, FeedbackRevoked, ResponseAppended |

## Modules

| Module | Type | Description |
|--------|------|-------------|
| `map_events` | map | Extracts all ERC-8004 events from both contracts |
| `store_agents` | store | Tracks agent owner, URI, and wallet state |
| `store_feedback_counts` | store | Aggregate feedback/response counts per agent |
| `store_reputation` | store | Running reputation scores per agent and tag |
| `map_flash_events` | map | Flashblocks streaming at 200ms latency (partial blocks safe) |
| `db_out` | map | Produces DatabaseChanges for PostgreSQL/ClickHouse |

## Quick Start

```bash
# Authenticate
substreams auth

# Build
substreams build

# Test with 1000 blocks
substreams run -s 25000000 -t +1000 map_events

# Visual debugger
substreams gui -s 25000000 -t +1000 map_events
```

## SQL Sinks

### PostgreSQL

```bash
docker compose up -d postgres
substreams-sink-sql setup "psql://erc8004:erc8004pass@localhost:5432/erc8004?sslmode=disable" ./erc8004-substreams-v0.2.0.spkg
substreams-sink-sql run "psql://erc8004:erc8004pass@localhost:5432/erc8004?sslmode=disable" ./erc8004-substreams-v0.2.0.spkg
```

### ClickHouse

```bash
docker compose up -d clickhouse
substreams-sink-sql setup "clickhouse://default:@localhost:9000/default" ./erc8004-substreams-v0.2.0.spkg
substreams-sink-sql run "clickhouse://default:@localhost:9000/default" ./erc8004-substreams-v0.2.0.spkg
```

The ClickHouse schema includes 6 materialized views for real-time analytics:
- Hourly registration stats
- Daily feedback volume per agent
- Per-tag feedback aggregates
- Top agents by activity
- Client activity leaderboard
- Hourly protocol metrics

## Database Tables

- `agents` — Agent identities (owner, URI, wallet)
- `agent_metadata` — Key-value metadata per agent
- `agent_transfers` — Transfer history
- `feedbacks` — All feedback entries with scores and tags
- `responses` — Feedback responses
- `identity_events` — Raw IdentityRegistry event log
- `reputation_events` — Raw ReputationRegistry event log

## Make Targets

```bash
make build              # Build WASM + spkg
make run                # Test run (1000 blocks)
make gui                # Visual debugger
make docker-up          # Start Postgres + ClickHouse + Grafana
make all-postgres       # Full setup: build + setup + run PostgreSQL sink
make all-clickhouse     # Full setup: build + setup + run ClickHouse sink
```

## Flashblocks (200ms Streaming)

Stream ERC-8004 events with 200ms latency using Base Flashblocks:

```bash
# Stream live with partial blocks
substreams run -e https://base-mainnet.streamingfast.io map_flash_events -s -1 --partial-blocks

# Visual debugger with Flashblocks
substreams gui -e https://base-mainnet.streamingfast.io map_flash_events -s -1 --partial-blocks

# Webhook sink for real-time notifications
substreams sink webhook --partial-blocks -e https://base-mainnet.streamingfast.io http://your-webhook.com ./erc8004-substreams-v0.2.0.spkg -s -1
```

The `map_flash_events` module only processes `transactionTraces` — no block-level aggregation — so it's safe for partial blocks. You get each ERC-8004 event as soon as it's sequenced by the Base sequencer, rather than waiting for full block confirmation.

## Links

- [ERC-8004 Standard](https://eips.ethereum.org/EIPS/eip-8004)
- [ERC-8004 Contracts](https://github.com/erc-8004/erc-8004-contracts)
- [Substreams Docs](https://substreams.streamingfast.io)
