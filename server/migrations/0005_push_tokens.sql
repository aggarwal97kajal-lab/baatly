-- Firebase Cloud Messaging tokens, one per logged-in phone (session).
CREATE TABLE push_tokens (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  session_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_push_user ON push_tokens(user_id);
