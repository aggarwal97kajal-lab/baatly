-- End-to-end encrypted messaging. The server only ever sees ciphertext.
CREATE TABLE user_keys (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  x25519     TEXT NOT NULL,           -- base64url public identity key (32 bytes)
  updated_at INTEGER NOT NULL
);

-- Events waiting for a phone to pick them up (messages + receipts).
-- Deleted as soon as the phone confirms it stored them.
CREATE TABLE inbox (
  id         TEXT PRIMARY KEY,
  to_user    TEXT NOT NULL,
  event      TEXT NOT NULL,           -- JSON; message bodies are encrypted
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_inbox_to ON inbox(to_user, created_at);
