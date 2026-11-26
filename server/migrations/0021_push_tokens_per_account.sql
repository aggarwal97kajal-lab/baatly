-- Two BAATLY accounts on one phone share the phone's push token: key by (token, user).
CREATE TABLE push_tokens_new (
  token      TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  session_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (token, user_id)
);
INSERT INTO push_tokens_new (token, user_id, session_id, updated_at) SELECT token, user_id, session_id, updated_at FROM push_tokens;
DROP TABLE push_tokens;
ALTER TABLE push_tokens_new RENAME TO push_tokens;
CREATE INDEX idx_push_user ON push_tokens(user_id);
