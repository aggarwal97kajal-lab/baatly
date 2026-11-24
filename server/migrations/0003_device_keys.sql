-- Fingerprint login: one Ed25519 key per phone, private key never leaves the phone.
CREATE TABLE device_keys (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  public_key   TEXT NOT NULL,          -- base64url raw 32-byte Ed25519 key
  device       TEXT NOT NULL DEFAULT '',
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER
);
CREATE INDEX idx_device_keys_user ON device_keys(user_id);
