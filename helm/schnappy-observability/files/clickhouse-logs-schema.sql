-- Plan 065 — log storage schema. Runs idempotently via the post-install
-- Helm hook (clickhouse-init-job).
--
-- The TTL clause references __TTL_DAYS__ which the init Job substitutes
-- from .Values.clickhouse.retention.days at apply time (sed -i in the
-- container) so the SQL file stays portable.

CREATE DATABASE IF NOT EXISTS logs;

CREATE TABLE IF NOT EXISTS logs.podlogs
(
    timestamp     DateTime64(3, 'UTC'),
    level         LowCardinality(String),
    namespace     LowCardinality(String),
    pod           String,
    container     LowCardinality(String),
    node          LowCardinality(String),
    app           LowCardinality(String),
    component     LowCardinality(String),
    stream        LowCardinality(String),
    message       String,
    labels        Map(LowCardinality(String), String),
    fields        Map(LowCardinality(String), String),
    INDEX idx_message_tokens tokens(message) TYPE bloom_filter GRANULARITY 4,
    INDEX idx_pod_bloom pod TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (namespace, app, timestamp)
TTL timestamp + INTERVAL __TTL_DAYS__ DAY DELETE
SETTINGS index_granularity = 8192;
