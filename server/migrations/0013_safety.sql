-- Block, report, and per-user rate limits (spam / abuse protection).
CREATE TABLE blocks (
  user_id    TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, blocked_id)
);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);

CREATE TABLE reports (
  id          TEXT PRIMARY KEY,
  reporter    TEXT NOT NULL,
  reported    TEXT NOT NULL,
  reason      TEXT NOT NULL,
  evidence    TEXT NOT NULL DEFAULT '',   -- last messages the reporter chose to share (plain text)
  created_at  INTEGER NOT NULL
);

CREATE TABLE rate_limits (
  k      TEXT PRIMARY KEY,   -- '<what>:<user>:<window>'
  n      INTEGER NOT NULL,
  expires INTEGER NOT NULL
);
CREATE INDEX idx_rate_expires ON rate_limits(expires);
