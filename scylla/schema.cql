CREATE KEYSPACE IF NOT EXISTS chat WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE IF NOT EXISTS chat.messages_by_channel (
    channel_id bigint,
    bucket text,
    message_id timeuuid,
    user_id bigint,
    username text,
    content text,
    parent_message_id text,
    edited boolean,
    deleted boolean,
    edited_content text,
    hash text,
    prev_hash text,
    key_version int,
    message_type text,
    metadata text,
    PRIMARY KEY ((channel_id, bucket), message_id)
) WITH CLUSTERING ORDER BY (message_id DESC)
  AND gc_grace_seconds = 864000;

CREATE TABLE IF NOT EXISTS chat.messages_by_user (
    user_id bigint,
    message_id timeuuid,
    channel_id bigint,
    bucket text,
    content text,
    PRIMARY KEY (user_id, message_id)
) WITH CLUSTERING ORDER BY (message_id DESC);

CREATE TABLE IF NOT EXISTS chat.message_edits (
    channel_id bigint,
    bucket text,
    message_id timeuuid,
    edit_id timeuuid,
    user_id bigint,
    content text,
    hash text,
    key_version int,
    PRIMARY KEY ((channel_id, bucket, message_id), edit_id)
) WITH CLUSTERING ORDER BY (edit_id DESC);

CREATE TABLE IF NOT EXISTS chat.chain_heads (
    channel_id bigint,
    hash text,
    message_id timeuuid,
    PRIMARY KEY (channel_id)
);

CREATE TABLE IF NOT EXISTS chat.reactions_by_message (
    channel_id bigint,
    bucket text,
    message_id timeuuid,
    emoji text,
    user_id bigint,
    username text,
    PRIMARY KEY ((channel_id, bucket, message_id), emoji, user_id)
);

CREATE TABLE IF NOT EXISTS chat.attachments_by_message (
    channel_id bigint,
    bucket text,
    message_id timeuuid,
    attachment_id timeuuid,
    url text,
    filename text,
    content_type text,
    size_bytes bigint,
    PRIMARY KEY ((channel_id, bucket, message_id), attachment_id)
);
