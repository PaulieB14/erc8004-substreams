.PHONY: build protogen run gui setup-postgres setup-clickhouse run-postgres run-clickhouse docker-up docker-down clean

# ─── Configuration ────────────────────────────────────────
SPKG           := erc8004-substreams-v0.1.0.spkg
POSTGRES_DSN   := psql://erc8004:erc8004pass@localhost:5432/erc8004?sslmode=disable
CLICKHOUSE_DSN := clickhouse://default:@localhost:9000/default
START_BLOCK    := 25000000
STOP_BLOCK     := +1000
MODULE         := map_events

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
