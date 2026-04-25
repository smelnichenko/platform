-- Log storage schema. Runs idempotently via the post-install
-- Helm hook (clickhouse-init-job).
--
-- The TTL clause references __TTL_DAYS__ which the init Job substitutes
-- from .Values.clickhouse.retention.days at apply time (sed -i in the
-- container) so the SQL file stays portable.
--
-- TTL must be wrapped in toDateTime() because ClickHouse 24.x rejects
-- TTL on a DateTime64 column directly (BAD_TTL_EXPRESSION).

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
    -- traceId/spanId promoted out of `fields` map for indexed lookup;
    -- empty string when the log line wasn't structured.
    trace_id      LowCardinality(String) DEFAULT '',
    span_id       LowCardinality(String) DEFAULT '',
    labels        Map(LowCardinality(String), String),
    fields        Map(LowCardinality(String), String),
    INDEX idx_message_tokens tokens(message) TYPE bloom_filter GRANULARITY 4,
    INDEX idx_pod_bloom pod TYPE bloom_filter GRANULARITY 4,
    INDEX idx_trace_id trace_id TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (namespace, app, timestamp)
TTL toDateTime(timestamp) + INTERVAL __TTL_DAYS__ DAY DELETE
SETTINGS index_granularity = 8192;

-- Online migration for clusters that pre-date the trace_id column.
-- Both ALTER and ADD INDEX are metadata-only on MergeTree.
ALTER TABLE logs.podlogs
    ADD COLUMN IF NOT EXISTS trace_id LowCardinality(String) DEFAULT '',
    ADD COLUMN IF NOT EXISTS span_id  LowCardinality(String) DEFAULT '';
ALTER TABLE logs.podlogs
    ADD INDEX IF NOT EXISTS idx_trace_id trace_id TYPE bloom_filter GRANULARITY 4;
