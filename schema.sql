-- ═══════════════════════════════════════════════════════════
-- ERC-8004 Trustless Agents — PostgreSQL Schema
-- ═══════════════════════════════════════════════════════════

-- ─── Agent Identities ────────────────────────────────────

CREATE TABLE IF NOT EXISTS agents (
    agent_id        TEXT PRIMARY KEY,
    owner           TEXT NOT NULL,
    agent_uri       TEXT NOT NULL DEFAULT '',
    agent_wallet    TEXT NOT NULL DEFAULT '',
    is_active       TEXT NOT NULL DEFAULT 'true',
    created_at      BIGINT NOT NULL,
    updated_at      BIGINT NOT NULL,
    created_tx      TEXT NOT NULL,
    block_number    BIGINT NOT NULL
);

CREATE INDEX idx_agents_owner ON agents(owner);
CREATE INDEX idx_agents_wallet ON agents(agent_wallet) WHERE agent_wallet != '';
CREATE INDEX idx_agents_created ON agents(created_at);

-- ─── Agent Metadata (Key-Value) ──────────────────────────

CREATE TABLE IF NOT EXISTS agent_metadata (
    id              TEXT PRIMARY KEY,  -- agentId:metadataKey
    agent_id        TEXT NOT NULL,
    metadata_key    TEXT NOT NULL,
    metadata_value  TEXT NOT NULL DEFAULT '',
    updated_at      BIGINT NOT NULL,
    tx_hash         TEXT NOT NULL
);

CREATE INDEX idx_metadata_agent ON agent_metadata(agent_id);
CREATE INDEX idx_metadata_key ON agent_metadata(metadata_key);

-- ─── Agent Transfer History ──────────────────────────────

CREATE TABLE IF NOT EXISTS agent_transfers (
    id              TEXT PRIMARY KEY,
    agent_id        TEXT NOT NULL,
    from_address    TEXT NOT NULL,
    to_address      TEXT NOT NULL,
    tx_hash         TEXT NOT NULL,
    block_number    BIGINT NOT NULL,
    block_timestamp BIGINT NOT NULL
);

CREATE INDEX idx_transfers_agent ON agent_transfers(agent_id);
CREATE INDEX idx_transfers_from ON agent_transfers(from_address);
CREATE INDEX idx_transfers_to ON agent_transfers(to_address);
CREATE INDEX idx_transfers_block ON agent_transfers(block_number);

-- ─── Feedbacks ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS feedbacks (
    id              TEXT PRIMARY KEY,  -- agentId:clientAddress:feedbackIndex
    agent_id        TEXT NOT NULL,
    client_address  TEXT NOT NULL,
    feedback_index  BIGINT NOT NULL,
    value           TEXT NOT NULL,
    value_decimals  BIGINT NOT NULL,
    tag1            TEXT NOT NULL DEFAULT '',
    tag2            TEXT NOT NULL DEFAULT '',
    endpoint        TEXT NOT NULL DEFAULT '',
    feedback_uri    TEXT NOT NULL DEFAULT '',
    feedback_hash   TEXT NOT NULL DEFAULT '',
    is_revoked      TEXT NOT NULL DEFAULT 'false',
    response_count  BIGINT NOT NULL DEFAULT 0,
    created_at      BIGINT NOT NULL,
    tx_hash         TEXT NOT NULL,
    block_number    BIGINT NOT NULL
);

CREATE INDEX idx_feedbacks_agent ON feedbacks(agent_id);
CREATE INDEX idx_feedbacks_client ON feedbacks(client_address);
CREATE INDEX idx_feedbacks_agent_client ON feedbacks(agent_id, client_address);
CREATE INDEX idx_feedbacks_tag1 ON feedbacks(tag1) WHERE tag1 != '';
CREATE INDEX idx_feedbacks_tag2 ON feedbacks(tag2) WHERE tag2 != '';
CREATE INDEX idx_feedbacks_active ON feedbacks(agent_id) WHERE is_revoked = 'false';
CREATE INDEX idx_feedbacks_block ON feedbacks(block_number);

-- ─── Responses ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS responses (
    id              TEXT PRIMARY KEY,  -- agentId:clientAddress:feedbackIndex:responder
    agent_id        TEXT NOT NULL,
    client_address  TEXT NOT NULL,
    feedback_index  BIGINT NOT NULL,
    responder       TEXT NOT NULL,
    response_uri    TEXT NOT NULL DEFAULT '',
    response_hash   TEXT NOT NULL DEFAULT '',
    created_at      BIGINT NOT NULL,
    tx_hash         TEXT NOT NULL,
    block_number    BIGINT NOT NULL
);

CREATE INDEX idx_responses_agent ON responses(agent_id);
CREATE INDEX idx_responses_feedback ON responses(agent_id, client_address, feedback_index);
CREATE INDEX idx_responses_responder ON responses(responder);

-- ─── Identity Events (all IdentityRegistry logs) ────────

CREATE TABLE IF NOT EXISTS identity_events (
    id              TEXT PRIMARY KEY,
    event_type      TEXT NOT NULL,
    agent_id        TEXT NOT NULL,
    owner           TEXT NOT NULL DEFAULT '',
    agent_uri       TEXT NOT NULL DEFAULT '',
    metadata_key    TEXT NOT NULL DEFAULT '',
    metadata_value  TEXT NOT NULL DEFAULT '',
    from_address    TEXT NOT NULL DEFAULT '',
    to_address      TEXT NOT NULL DEFAULT '',
    tx_hash         TEXT NOT NULL,
    block_number    BIGINT NOT NULL,
    log_index       BIGINT NOT NULL,
    block_timestamp BIGINT NOT NULL
);

CREATE INDEX idx_identity_events_agent ON identity_events(agent_id);
CREATE INDEX idx_identity_events_type ON identity_events(event_type);
CREATE INDEX idx_identity_events_block ON identity_events(block_number);
CREATE INDEX idx_identity_events_tx ON identity_events(tx_hash);

-- ─── Reputation Events (all ReputationRegistry logs) ────

CREATE TABLE IF NOT EXISTS reputation_events (
    id              TEXT PRIMARY KEY,
    event_type      TEXT NOT NULL,
    agent_id        TEXT NOT NULL,
    client_address  TEXT NOT NULL DEFAULT '',
    feedback_index  BIGINT NOT NULL DEFAULT 0,
    value           TEXT NOT NULL DEFAULT '',
    value_decimals  BIGINT NOT NULL DEFAULT 0,
    tag1            TEXT NOT NULL DEFAULT '',
    tag2            TEXT NOT NULL DEFAULT '',
    endpoint        TEXT NOT NULL DEFAULT '',
    feedback_uri    TEXT NOT NULL DEFAULT '',
    feedback_hash   TEXT NOT NULL DEFAULT '',
    responder       TEXT NOT NULL DEFAULT '',
    response_uri    TEXT NOT NULL DEFAULT '',
    response_hash   TEXT NOT NULL DEFAULT '',
    tx_hash         TEXT NOT NULL,
    block_number    BIGINT NOT NULL,
    log_index       BIGINT NOT NULL,
    block_timestamp BIGINT NOT NULL
);

CREATE INDEX idx_reputation_events_agent ON reputation_events(agent_id);
CREATE INDEX idx_reputation_events_type ON reputation_events(event_type);
CREATE INDEX idx_reputation_events_client ON reputation_events(client_address);
CREATE INDEX idx_reputation_events_block ON reputation_events(block_number);
CREATE INDEX idx_reputation_events_tag1 ON reputation_events(tag1) WHERE tag1 != '';
CREATE INDEX idx_reputation_events_tx ON reputation_events(tx_hash);

-- ─── Views for Analytics ─────────────────────────────────

CREATE OR REPLACE VIEW agent_reputation_summary AS
SELECT
    f.agent_id,
    COUNT(*) FILTER (WHERE f.is_revoked = 'false') AS active_feedback_count,
    COUNT(*) AS total_feedback_count,
    COUNT(DISTINCT f.client_address) AS unique_clients,
    COUNT(*) FILTER (WHERE f.is_revoked = 'true') AS revoked_count
FROM feedbacks f
GROUP BY f.agent_id;

CREATE OR REPLACE VIEW agent_tag_breakdown AS
SELECT
    f.agent_id,
    f.tag1,
    COUNT(*) FILTER (WHERE f.is_revoked = 'false') AS feedback_count,
    COUNT(DISTINCT f.client_address) AS unique_clients
FROM feedbacks f
WHERE f.tag1 != ''
GROUP BY f.agent_id, f.tag1;

CREATE OR REPLACE VIEW recent_activity AS
SELECT
    re.event_type,
    re.agent_id,
    re.client_address,
    re.tx_hash,
    re.block_number,
    re.block_timestamp
FROM reputation_events re
ORDER BY re.block_number DESC, re.log_index DESC;
