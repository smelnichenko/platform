-- Events database fed from Kafka. Runs idempotently via the post-install
-- Helm hook. Kafka engine + materialized view stream envelopes from the
-- configured topics into events.all (MergeTree).
--
-- Substituted at apply time by the init Job:
--   __KAFKA_BROKERS__  → comma-joined broker list
--   __KAFKA_TOPICS__   → comma-joined topic list
--   __KAFKA_GROUP__    → consumer group name
--   __KAFKA_NUM_CONS__ → kafka_num_consumers
--   __EVT_TTL_DAYS__   → MergeTree TTL in days

CREATE DATABASE IF NOT EXISTS events;

CREATE TABLE IF NOT EXISTS events.kafka_stream
(
    id            UUID,
    type          LowCardinality(String),
    version       UInt8,
    ts            DateTime64(3, 'UTC'),
    service       LowCardinality(String),
    subject       String,
    actor         String,
    payload       String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list   = '__KAFKA_BROKERS__',
    kafka_topic_list    = '__KAFKA_TOPICS__',
    kafka_group_name    = '__KAFKA_GROUP__',
    kafka_format        = 'JSONEachRow',
    kafka_num_consumers = __KAFKA_NUM_CONS__;

CREATE TABLE IF NOT EXISTS events.all
(
    id            UUID,
    type          LowCardinality(String),
    version       UInt8,
    ts            DateTime64(3, 'UTC'),
    service       LowCardinality(String),
    subject       String,
    actor         String,
    payload       String,
    INDEX idx_actor   actor   TYPE bloom_filter GRANULARITY 4,
    INDEX idx_subject subject TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service, type, ts)
TTL ts + INTERVAL __EVT_TTL_DAYS__ DAY DELETE;

CREATE MATERIALIZED VIEW IF NOT EXISTS events.ingest TO events.all AS
SELECT * FROM events.kafka_stream;
