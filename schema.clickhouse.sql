-- ═══════════════════════════════════════════════════════════
-- ERC-8004 Trustless Agents — ClickHouse Schema
-- ═══════════════════════════════════════════════════════════

-- ─── Agent Identities ────────────────────────────────────

CREATE TABLE IF NOT EXISTS agents (
    agent_id        String,
    owner           String,
    agent_uri       String DEFAULT '',
    agent_wallet    String DEFAULT '',
    is_active       String DEFAULT 'true',
    created_at      Int64,
    updated_at      Int64,
    created_tx      String,
    block_number    Int64
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY agent_id
SETTINGS index_granularity = 8192;

-- ─── Agent Metadata (Key-Value) ──────────────────────────

CREATE TABLE IF NOT EXISTS agent_metadata (
    id              String,
    agent_id        String,
    metadata_key    String,
    metadata_value  String DEFAULT '',
    updated_at      Int64,
    tx_hash         String
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id
SETTINGS index_granularity = 8192;

-- ─── Agent Transfer History ──────────────────────────────

CREATE TABLE IF NOT EXISTS agent_transfers (
    id              String,
    agent_id        String,
    from_address    String,
    to_address      String,
    tx_hash         String,
    block_number    Int64,
    block_timestamp Int64
) ENGINE = MergeTree()
ORDER BY (agent_id, block_number)
SETTINGS index_granularity = 8192;

-- ─── Feedbacks ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS feedbacks (
    id              String,
    agent_id        String,
    client_address  String,
    feedback_index  Int64,
    value           String,
    value_decimals  Int64,
    tag1            String DEFAULT '',
    tag2            String DEFAULT '',
    endpoint        String DEFAULT '',
    feedback_uri    String DEFAULT '',
    feedback_hash   String DEFAULT '',
    is_revoked      String DEFAULT 'false',
    response_count  Int64 DEFAULT 0,
    created_at      Int64,
    tx_hash         String,
    block_number    Int64
) ENGINE = ReplacingMergeTree(block_number)
ORDER BY id
SETTINGS index_granularity = 8192;

-- ─── Responses ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS responses (
    id              String,
    agent_id        String,
    client_address  String,
    feedback_index  Int64,
    responder       String,
    response_uri    String DEFAULT '',
    response_hash   String DEFAULT '',
    created_at      Int64,
    tx_hash         String,
    block_number    Int64
) ENGINE = MergeTree()
ORDER BY (agent_id, client_address, feedback_index, responder)
SETTINGS index_granularity = 8192;

-- ─── Identity Events ────────────────────────────────────

CREATE TABLE IF NOT EXISTS identity_events (
    id              String,
    event_type      LowCardinality(String),
    agent_id        String,
    owner           String DEFAULT '',
    agent_uri       String DEFAULT '',
    metadata_key    String DEFAULT '',
    metadata_value  String DEFAULT '',
    from_address    String DEFAULT '',
    to_address      String DEFAULT '',
    tx_hash         String,
    block_number    Int64,
    log_index       Int64,
    block_timestamp Int64,

    -- Pre-computed for time-series
    event_date      Date DEFAULT toDate(toDateTime(block_timestamp)),
    event_hour      DateTime DEFAULT toStartOfHour(toDateTime(block_timestamp))
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (agent_id, block_number, log_index)
SETTINGS index_granularity = 8192;

-- ─── Reputation Events ──────────────────────────────────

CREATE TABLE IF NOT EXISTS reputation_events (
    id              String,
    event_type      LowCardinality(String),
    agent_id        String,
    client_address  String DEFAULT '',
    feedback_index  Int64 DEFAULT 0,
    value           String DEFAULT '',
    value_decimals  Int64 DEFAULT 0,
    tag1            String DEFAULT '',
    tag2            String DEFAULT '',
    endpoint        String DEFAULT '',
    feedback_uri    String DEFAULT '',
    feedback_hash   String DEFAULT '',
    responder       String DEFAULT '',
    response_uri    String DEFAULT '',
    response_hash   String DEFAULT '',
    tx_hash         String,
    block_number    Int64,
    log_index       Int64,
    block_timestamp Int64,

    -- Pre-computed for time-series
    event_date      Date DEFAULT toDate(toDateTime(block_timestamp)),
    event_hour      DateTime DEFAULT toStartOfHour(toDateTime(block_timestamp))
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (agent_id, block_number, log_index)
SETTINGS index_granularity = 8192;

-- ═══════════════════════════════════════════════════════════
-- Materialized Views — Real-time Analytics
-- ═══════════════════════════════════════════════════════════

-- ─── Hourly Registration Stats ───────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_registrations
ENGINE = SummingMergeTree()
ORDER BY event_hour
AS SELECT
    event_hour,
    count() AS registration_count
FROM identity_events
WHERE event_type = 'registered'
GROUP BY event_hour;

-- ─── Daily Feedback Volume ───────────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_feedback_volume
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, agent_id)
AS SELECT
    event_date,
    agent_id,
    countIf(event_type = 'new_feedback') AS feedback_count,
    countIf(event_type = 'feedback_revoked') AS revocation_count,
    countIf(event_type = 'response_appended') AS response_count
FROM reputation_events
GROUP BY event_date, agent_id;

-- ─── Per-Tag Feedback Aggregates ─────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_tag_aggregates
ENGINE = SummingMergeTree()
ORDER BY (agent_id, tag1)
AS SELECT
    agent_id,
    tag1,
    count() AS feedback_count,
    uniqExact(client_address) AS unique_clients
FROM reputation_events
WHERE event_type = 'new_feedback' AND tag1 != ''
GROUP BY agent_id, tag1;

-- ─── Top Agents by Activity ─────────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_agent_activity
ENGINE = SummingMergeTree()
ORDER BY agent_id
AS SELECT
    agent_id,
    countIf(event_type = 'new_feedback') AS total_feedbacks,
    countIf(event_type = 'response_appended') AS total_responses,
    uniqExactIf(client_address, event_type = 'new_feedback') AS unique_clients
FROM reputation_events
GROUP BY agent_id;

-- ─── Client Activity Leaderboard ─────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_client_activity
ENGINE = SummingMergeTree()
ORDER BY client_address
AS SELECT
    client_address,
    count() AS total_feedbacks_given,
    uniqExact(agent_id) AS agents_reviewed
FROM reputation_events
WHERE event_type = 'new_feedback'
GROUP BY client_address;

-- ─── Hourly Protocol Metrics ─────────────────────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_protocol_hourly
ENGINE = SummingMergeTree()
ORDER BY (metric_hour)
AS SELECT
    event_hour AS metric_hour,
    countIf(event_type = 'new_feedback') AS feedbacks,
    countIf(event_type = 'feedback_revoked') AS revocations,
    countIf(event_type = 'response_appended') AS responses
FROM reputation_events
GROUP BY event_hour;
