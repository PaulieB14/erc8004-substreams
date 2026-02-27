mod abi;

use abi::identity_registry::events as identity_events;
use abi::reputation_registry::events as reputation_events;
use hex;
use substreams::errors::Error;
use substreams::prelude::*;
use substreams::store::{
    StoreAddInt64, StoreGet, StoreGetString, StoreNew, StoreSet, StoreSetString,
};
use substreams_database_change::pb::sf::substreams::sink::database::v1::DatabaseChanges;
use substreams_database_change::tables::Tables;
use substreams_ethereum::pb::eth::v2::Block;
use substreams_ethereum::Event;

#[allow(dead_code)]
#[path = "pb/erc8004.v1.rs"]
mod pb;

use pb::*;

// ─────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────

const DEFAULT_IDENTITY_REGISTRY: &str = "8004a169fb4a3325136eb29fa0ceb6d2e539a432";
const DEFAULT_REPUTATION_REGISTRY: &str = "8004baa17c55a88189ae136b182e5fda19de9b63";

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────

fn parse_params(params: &str) -> (Vec<u8>, Vec<u8>) {
    let mut identity_addr = hex::decode(DEFAULT_IDENTITY_REGISTRY).unwrap();
    let mut reputation_addr = hex::decode(DEFAULT_REPUTATION_REGISTRY).unwrap();

    for part in params.split(',') {
        let kv: Vec<&str> = part.split('=').collect();
        if kv.len() == 2 {
            let key = kv[0].trim();
            let val = kv[1].trim().trim_start_matches("0x");
            if let Ok(bytes) = hex::decode(val) {
                match key {
                    "identity_registry" => identity_addr = bytes,
                    "reputation_registry" => reputation_addr = bytes,
                    _ => {}
                }
            }
        }
    }

    (identity_addr, reputation_addr)
}

fn format_address(addr: &[u8]) -> String {
    format!("0x{}", hex::encode(addr))
}

fn format_token_id(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return "0".to_string();
    }
    let bi = num_bigint::BigUint::from_bytes_be(bytes);
    bi.to_string()
}

fn format_int128(bytes: &[u8]) -> String {
    if bytes.len() < 16 {
        return "0".to_string();
    }
    // int128 is stored as 32 bytes (sign-extended), take last 16 bytes
    let start = if bytes.len() > 16 { bytes.len() - 16 } else { 0 };
    let slice = &bytes[start..];
    let mut arr = [0u8; 16];
    arr.copy_from_slice(slice);
    let val = i128::from_be_bytes(arr);
    val.to_string()
}

// ─────────────────────────────────────────────────────────
// map_events — Extract all ERC-8004 events
// ─────────────────────────────────────────────────────────

#[substreams::handlers::map]
pub fn map_events(params: String, block: Block) -> Result<Events, Error> {
    let (identity_addr, reputation_addr) = parse_params(&params);
    let timestamp = block
        .header
        .as_ref()
        .map(|h| h.timestamp.as_ref().map(|t| t.seconds as u64).unwrap_or(0))
        .unwrap_or(0);
    let block_number = block.number;

    let mut events = Events::default();

    for trx in block.transactions() {
        let tx_hash = format_address(&trx.hash);

        for (log, _call) in trx.logs_with_calls() {
            let log_index = log.block_index as u64;

            // ─── IdentityRegistry events ─────────────────
            if log.address == identity_addr {
                // Registered(uint256 agentId, string agentURI, address owner)
                if let Some(evt) = identity_events::Registered::match_and_decode(log) {
                    events.registrations.push(AgentRegistered {
                        agent_id: evt.agent_id.to_string(),
                        agent_uri: evt.agent_uri,
                        owner: format_address(&evt.owner),
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }

                // Transfer(address from, address to, uint256 tokenId)
                if let Some(evt) = identity_events::Transfer::match_and_decode(log) {
                    events.transfers.push(AgentTransfer {
                        agent_id: evt.token_id.to_string(),
                        from: format_address(&evt.from),
                        to: format_address(&evt.to),
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }

                // MetadataSet(uint256 agentId, string indexedMetadataKey, string metadataKey, bytes metadataValue)
                if let Some(evt) = identity_events::MetadataSet::match_and_decode(log) {
                    events.metadata_sets.push(pb::MetadataSet {
                        agent_id: evt.agent_id.to_string(),
                        metadata_key: evt.metadata_key,
                        metadata_value: evt.metadata_value,
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }

                // URIUpdated(uint256 agentId, string newURI, address updatedBy)
                if let Some(evt) = identity_events::UriUpdated::match_and_decode(log) {
                    events.uri_updates.push(UriUpdated {
                        agent_id: evt.agent_id.to_string(),
                        new_uri: evt.new_uri,
                        updated_by: format_address(&evt.updated_by),
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }
            }

            // ─── ReputationRegistry events ───────────────
            if log.address == reputation_addr {
                // NewFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex,
                //   int128 value, uint8 valueDecimals, string indexedTag1,
                //   string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)
                if let Some(evt) = reputation_events::NewFeedback::match_and_decode(log) {
                    events.feedbacks.push(pb::NewFeedback {
                        agent_id: evt.agent_id.to_string(),
                        client_address: format_address(&evt.client_address),
                        feedback_index: evt.feedback_index,
                        value: evt.value.to_string(),
                        value_decimals: evt.value_decimals as u32,
                        tag1: evt.tag1,
                        tag2: evt.tag2,
                        endpoint: evt.endpoint,
                        feedback_uri: evt.feedback_uri,
                        feedback_hash: format!("0x{}", hex::encode(&evt.feedback_hash)),
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }

                // FeedbackRevoked(uint256 agentId, address clientAddress, uint64 feedbackIndex)
                if let Some(evt) = reputation_events::FeedbackRevoked::match_and_decode(log) {
                    events.feedback_revocations.push(pb::FeedbackRevoked {
                        agent_id: evt.agent_id.to_string(),
                        client_address: format_address(&evt.client_address),
                        feedback_index: evt.feedback_index,
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }

                // ResponseAppended(uint256 agentId, address clientAddress, uint64 feedbackIndex,
                //   address responder, string responseURI, bytes32 responseHash)
                if let Some(evt) = reputation_events::ResponseAppended::match_and_decode(log) {
                    events.responses.push(pb::ResponseAppended {
                        agent_id: evt.agent_id.to_string(),
                        client_address: format_address(&evt.client_address),
                        feedback_index: evt.feedback_index,
                        responder: format_address(&evt.responder),
                        response_uri: evt.response_uri,
                        response_hash: format!("0x{}", hex::encode(&evt.response_hash)),
                        tx_hash: tx_hash.clone(),
                        block_number,
                        log_index,
                        timestamp,
                    });
                }
            }
        }
    }

    Ok(events)
}

// ─────────────────────────────────────────────────────────
// store_agents — Track agent identity state
// ─────────────────────────────────────────────────────────

#[substreams::handlers::store]
pub fn store_agents(events: Events, store: StoreSetString) {
    // On registration: set initial state
    for reg in &events.registrations {
        let state = format!("{}|{}|", reg.owner, reg.agent_uri);
        store.set(reg.log_index, format!("agent:{}", reg.agent_id), &state);
    }

    // On transfer: update owner, clear wallet
    for xfer in &events.transfers {
        store.set(
            xfer.log_index,
            format!("agent:{}", xfer.agent_id),
            &format!("{}||", xfer.to), // wallet cleared on transfer
        );
    }

    // On URI update
    for uri in &events.uri_updates {
        store.set(
            uri.log_index,
            format!("uri:{}", uri.agent_id),
            &uri.new_uri,
        );
    }

    // On metadata set (track agent wallet specifically)
    for meta in &events.metadata_sets {
        if meta.metadata_key == "agentWallet" {
            let wallet = if meta.metadata_value.is_empty() {
                String::new()
            } else {
                format_address(&meta.metadata_value)
            };
            store.set(
                meta.log_index,
                format!("wallet:{}", meta.agent_id),
                &wallet,
            );
        }
    }
}

// ─────────────────────────────────────────────────────────
// store_feedback_counts — Aggregate feedback metrics
// ─────────────────────────────────────────────────────────

#[substreams::handlers::store]
pub fn store_feedback_counts(events: Events, store: StoreAddInt64) {
    for fb in &events.feedbacks {
        store.add(fb.log_index, format!("feedback_total:{}", fb.agent_id), 1);
        store.add(
            fb.log_index,
            format!("feedback_active:{}", fb.agent_id),
            1,
        );
        // Per-client count
        store.add(
            fb.log_index,
            format!("client_count:{}:{}", fb.agent_id, fb.client_address),
            1,
        );
    }

    for rev in &events.feedback_revocations {
        store.add(
            rev.log_index,
            format!("feedback_active:{}", rev.agent_id),
            -1,
        );
    }

    for resp in &events.responses {
        store.add(
            resp.log_index,
            format!("responses:{}", resp.agent_id),
            1,
        );
    }
}

// ─────────────────────────────────────────────────────────
// store_reputation — Running reputation aggregates
// ─────────────────────────────────────────────────────────

#[substreams::handlers::store]
pub fn store_reputation(events: Events, store: StoreSetString) {
    for fb in &events.feedbacks {
        // We store as "sum|count" for later average calculation
        let key = format!("rep:{}", fb.agent_id);
        // Note: In a real scenario you'd read-then-update, but stores are
        // append-only. We store each feedback's contribution and compute
        // aggregates in db_out from deltas.
        store.set(
            fb.log_index,
            &key,
            &format!("{}|{}|{}", fb.value, fb.value_decimals, fb.feedback_index),
        );

        // Per-tag reputation
        if !fb.tag1.is_empty() {
            store.set(
                fb.log_index,
                format!("rep:{}:tag:{}", fb.agent_id, fb.tag1),
                &format!("{}|{}", fb.value, fb.value_decimals),
            );
        }
    }
}

// ─────────────────────────────────────────────────────────
// db_out — Produce DatabaseChanges for SQL sinks
// ─────────────────────────────────────────────────────────

#[substreams::handlers::map]
pub fn db_out(
    events: Events,
    agents_deltas: Deltas<DeltaString>,
    feedback_count_deltas: Deltas<DeltaInt64>,
    reputation_deltas: Deltas<DeltaString>,
) -> Result<DatabaseChanges, Error> {
    let mut tables = Tables::new();

    // ─── Agent Registrations ─────────────────────────────
    for reg in &events.registrations {
        let id = format!("{}-{}-{}", reg.tx_hash, reg.block_number, reg.log_index);

        // Event log
        tables
            .create_row("identity_events", &id)
            .set("event_type", "registered")
            .set("agent_id", &reg.agent_id)
            .set("owner", &reg.owner)
            .set("agent_uri", &reg.agent_uri)
            .set("metadata_key", "")
            .set("metadata_value", "")
            .set("from_address", "")
            .set("to_address", "")
            .set("tx_hash", &reg.tx_hash)
            .set("block_number", reg.block_number as i64)
            .set("log_index", reg.log_index as i64)
            .set("block_timestamp", reg.timestamp as i64);

        // Upsert agent identity
        tables
            .create_row("agents", &reg.agent_id)
            .set("agent_id", &reg.agent_id)
            .set("owner", &reg.owner)
            .set("agent_uri", &reg.agent_uri)
            .set("agent_wallet", "")
            .set("is_active", "true")
            .set("created_at", reg.timestamp as i64)
            .set("updated_at", reg.timestamp as i64)
            .set("created_tx", &reg.tx_hash)
            .set("block_number", reg.block_number as i64);
    }

    // ─── Agent Transfers ─────────────────────────────────
    for xfer in &events.transfers {
        let id = format!("{}-{}-{}", xfer.tx_hash, xfer.block_number, xfer.log_index);

        tables
            .create_row("identity_events", &id)
            .set("event_type", "transfer")
            .set("agent_id", &xfer.agent_id)
            .set("owner", "")
            .set("agent_uri", "")
            .set("metadata_key", "")
            .set("metadata_value", "")
            .set("from_address", &xfer.from)
            .set("to_address", &xfer.to)
            .set("tx_hash", &xfer.tx_hash)
            .set("block_number", xfer.block_number as i64)
            .set("log_index", xfer.log_index as i64)
            .set("block_timestamp", xfer.timestamp as i64);

        // Transfer history
        tables
            .create_row("agent_transfers", &id)
            .set("agent_id", &xfer.agent_id)
            .set("from_address", &xfer.from)
            .set("to_address", &xfer.to)
            .set("tx_hash", &xfer.tx_hash)
            .set("block_number", xfer.block_number as i64)
            .set("block_timestamp", xfer.timestamp as i64);
    }

    // ─── Metadata Changes ────────────────────────────────
    for meta in &events.metadata_sets {
        let id = format!("{}-{}-{}", meta.tx_hash, meta.block_number, meta.log_index);

        tables
            .create_row("identity_events", &id)
            .set("event_type", "metadata_set")
            .set("agent_id", &meta.agent_id)
            .set("owner", "")
            .set("agent_uri", "")
            .set("metadata_key", &meta.metadata_key)
            .set("metadata_value", &hex::encode(&meta.metadata_value))
            .set("from_address", "")
            .set("to_address", "")
            .set("tx_hash", &meta.tx_hash)
            .set("block_number", meta.block_number as i64)
            .set("log_index", meta.log_index as i64)
            .set("block_timestamp", meta.timestamp as i64);

        // Agent metadata KV store
        let meta_id = format!("{}:{}", meta.agent_id, meta.metadata_key);
        tables
            .create_row("agent_metadata", &meta_id)
            .set("agent_id", &meta.agent_id)
            .set("metadata_key", &meta.metadata_key)
            .set("metadata_value", &hex::encode(&meta.metadata_value))
            .set("updated_at", meta.timestamp as i64)
            .set("tx_hash", &meta.tx_hash);
    }

    // ─── URI Updates ─────────────────────────────────────
    for uri in &events.uri_updates {
        let id = format!("{}-{}-{}", uri.tx_hash, uri.block_number, uri.log_index);

        tables
            .create_row("identity_events", &id)
            .set("event_type", "uri_updated")
            .set("agent_id", &uri.agent_id)
            .set("owner", &uri.updated_by)
            .set("agent_uri", &uri.new_uri)
            .set("metadata_key", "")
            .set("metadata_value", "")
            .set("from_address", "")
            .set("to_address", "")
            .set("tx_hash", &uri.tx_hash)
            .set("block_number", uri.block_number as i64)
            .set("log_index", uri.log_index as i64)
            .set("block_timestamp", uri.timestamp as i64);
    }

    // ─── New Feedback ────────────────────────────────────
    for fb in &events.feedbacks {
        let id = format!("{}-{}-{}", fb.tx_hash, fb.block_number, fb.log_index);

        // Feedback event log
        tables
            .create_row("reputation_events", &id)
            .set("event_type", "new_feedback")
            .set("agent_id", &fb.agent_id)
            .set("client_address", &fb.client_address)
            .set("feedback_index", fb.feedback_index as i64)
            .set("value", &fb.value)
            .set("value_decimals", fb.value_decimals as i64)
            .set("tag1", &fb.tag1)
            .set("tag2", &fb.tag2)
            .set("endpoint", &fb.endpoint)
            .set("feedback_uri", &fb.feedback_uri)
            .set("feedback_hash", &fb.feedback_hash)
            .set("responder", "")
            .set("response_uri", "")
            .set("response_hash", "")
            .set("tx_hash", &fb.tx_hash)
            .set("block_number", fb.block_number as i64)
            .set("log_index", fb.log_index as i64)
            .set("block_timestamp", fb.timestamp as i64);

        // Feedback record
        let fb_key = format!("{}:{}:{}", fb.agent_id, fb.client_address, fb.feedback_index);
        tables
            .create_row("feedbacks", &fb_key)
            .set("agent_id", &fb.agent_id)
            .set("client_address", &fb.client_address)
            .set("feedback_index", fb.feedback_index as i64)
            .set("value", &fb.value)
            .set("value_decimals", fb.value_decimals as i64)
            .set("tag1", &fb.tag1)
            .set("tag2", &fb.tag2)
            .set("endpoint", &fb.endpoint)
            .set("feedback_uri", &fb.feedback_uri)
            .set("feedback_hash", &fb.feedback_hash)
            .set("is_revoked", "false")
            .set("response_count", 0i64)
            .set("created_at", fb.timestamp as i64)
            .set("tx_hash", &fb.tx_hash)
            .set("block_number", fb.block_number as i64);
    }

    // ─── Feedback Revocations ────────────────────────────
    for rev in &events.feedback_revocations {
        let id = format!("{}-{}-{}", rev.tx_hash, rev.block_number, rev.log_index);

        tables
            .create_row("reputation_events", &id)
            .set("event_type", "feedback_revoked")
            .set("agent_id", &rev.agent_id)
            .set("client_address", &rev.client_address)
            .set("feedback_index", rev.feedback_index as i64)
            .set("value", "")
            .set("value_decimals", 0i64)
            .set("tag1", "")
            .set("tag2", "")
            .set("endpoint", "")
            .set("feedback_uri", "")
            .set("feedback_hash", "")
            .set("responder", "")
            .set("response_uri", "")
            .set("response_hash", "")
            .set("tx_hash", &rev.tx_hash)
            .set("block_number", rev.block_number as i64)
            .set("log_index", rev.log_index as i64)
            .set("block_timestamp", rev.timestamp as i64);
    }

    // ─── Responses ───────────────────────────────────────
    for resp in &events.responses {
        let id = format!("{}-{}-{}", resp.tx_hash, resp.block_number, resp.log_index);

        tables
            .create_row("reputation_events", &id)
            .set("event_type", "response_appended")
            .set("agent_id", &resp.agent_id)
            .set("client_address", &resp.client_address)
            .set("feedback_index", resp.feedback_index as i64)
            .set("value", "")
            .set("value_decimals", 0i64)
            .set("tag1", "")
            .set("tag2", "")
            .set("endpoint", "")
            .set("feedback_uri", "")
            .set("feedback_hash", "")
            .set("responder", &resp.responder)
            .set("response_uri", &resp.response_uri)
            .set("response_hash", &resp.response_hash)
            .set("tx_hash", &resp.tx_hash)
            .set("block_number", resp.block_number as i64)
            .set("log_index", resp.log_index as i64)
            .set("block_timestamp", resp.timestamp as i64);

        // Response record
        let resp_key = format!(
            "{}:{}:{}:{}",
            resp.agent_id, resp.client_address, resp.feedback_index, resp.responder
        );
        tables
            .create_row("responses", &resp_key)
            .set("agent_id", &resp.agent_id)
            .set("client_address", &resp.client_address)
            .set("feedback_index", resp.feedback_index as i64)
            .set("responder", &resp.responder)
            .set("response_uri", &resp.response_uri)
            .set("response_hash", &resp.response_hash)
            .set("created_at", resp.timestamp as i64)
            .set("tx_hash", &resp.tx_hash)
            .set("block_number", resp.block_number as i64);
    }

    Ok(tables.to_database_changes())
}
