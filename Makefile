.PHONY: build protogen run gui flash flash-gui setup-postgres setup-clickhouse run-postgres run-clickhouse docker-up docker-down clean

# ─── Configuration ────────────────────────────────────────
SPKG           := erc8004-substreams-v0.3.0.spkg
BASE_ENDPOINT  := https://base-mainnet.streamingfast.io
POSTGRES_DSN   := psql://erc8004:erc8004pass@localhost:5432/erc8004?sslmode=disable
CLICKHOUSE_DSN := clickhouse://default:@localhost:9000/default
START_BLOCK    := 41663783
STOP_BLOCK     := +1000
MODULE         := map_events

# Set SUBSTREAMS_API_TOKEN env var or pass TOKEN= on command line
# Example: make gui TOKEN=eyJhbG...
ifdef TOKEN
export SUBSTREAMS_API_TOKEN := $(TOKEN)
endif

# ─── Build ────────────────────────────────────────────────

protogen:
	substreams protogen

build:
	substreams build

# ─── Run & Debug ──────────────────────────────────────────

run:
	substreams run -s $(START_BLOCK) -t $(STOP_BLOCK) $(MODULE)

run-production:
	substreams run -s $(START_BLOCK) -t $(STOP_BLOCK) $(MODULE) --production-mode

gui:
	substreams gui -s $(START_BLOCK) -t $(STOP_BLOCK) $(MODULE)

graph:
	substreams graph

# ─── Flashblocks (200ms streaming) ───────────────────────

flash:
	substreams run -e $(BASE_ENDPOINT) map_flash_events -s -1 --partial-blocks

flash-gui:
	substreams gui -e $(BASE_ENDPOINT) map_flash_events -s -1 --partial-blocks

# ─── Docker Infrastructure ───────────────────────────────

docker-up:
	docker compose up -d

docker-down:
	docker compose down

docker-reset:
	docker compose down -v
	docker compose up -d

# ─── PostgreSQL Sink ─────────────────────────────────────

setup-postgres: build
	substreams-sink-sql setup "$(POSTGRES_DSN)" ./$(SPKG)

run-postgres: build
	substreams-sink-sql run "$(POSTGRES_DSN)" ./$(SPKG)

run-postgres-dev: build
	substreams-sink-sql run --development-mode "$(POSTGRES_DSN)" ./$(SPKG)

# ─── ClickHouse Sink ─────────────────────────────────────

setup-clickhouse: build
	substreams-sink-sql setup "$(CLICKHOUSE_DSN)" ./$(SPKG)

run-clickhouse: build
	substreams-sink-sql run "$(CLICKHOUSE_DSN)" ./$(SPKG)

run-clickhouse-dev: build
	substreams-sink-sql run --development-mode "$(CLICKHOUSE_DSN)" ./$(SPKG)

# ─── Utilities ───────────────────────────────────────────

clean:
	rm -rf target
	rm -f *.spkg

auth:
	substreams auth

check-postgres:
	psql "$(POSTGRES_DSN)" -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"

check-clickhouse:
	clickhouse-client --query "SHOW TABLES"

# ─── Full Setup (from scratch) ───────────────────────────

all-postgres: docker-up build setup-postgres run-postgres

all-clickhouse: docker-up build setup-clickhouse run-clickhouse
