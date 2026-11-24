-- BAATLY auth schema (Milestone 2)

CREATE TABLE users (
  id          TEXT PRIMARY KEY,                -- random id, also the passkey user handle
  phone       TEXT NOT NULL UNIQUE,            -- E.164, e.g. +919876543210
  name        TEXT NOT NULL DEFAULT '',
  username    TEXT UNIQUE,                     -- lowercase, nullable until chosen
  about       TEXT NOT NULL DEFAULT 'Baat karte hain!',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

-- One row per logged-in device. Token stored only as SHA-256 hash.
CREATE TABLE sessions (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT NOT NULL UNIQUE,
  device       TEXT NOT NULL DEFAULT '',
  method       TEXT NOT NULL,                  -- 'otp' | 'passkey'
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);
CREATE INDEX idx_sessions_user ON sessions(user_id);

CREATE TABLE passkeys (
  id          TEXT PRIMARY KEY,                -- credential id (base64url)
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  public_key  TEXT NOT NULL,                   -- base64url COSE key
  counter     INTEGER NOT NULL DEFAULT 0,
  transports  TEXT NOT NULL DEFAULT '[]',      -- JSON array
  device      TEXT NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL,
  last_used_at INTEGER
);
CREATE INDEX idx_passkeys_user ON passkeys(user_id);

-- OTP requests: maps our opaque request id to the provider's verification id,
-- and is used for rate limiting. Never stores the OTP itself.
CREATE TABLE otp_requests (
  id               TEXT PRIMARY KEY,
  phone            TEXT NOT NULL,
  ip               TEXT NOT NULL DEFAULT '',
  provider_ref     TEXT NOT NULL,
  attempts         INTEGER NOT NULL DEFAULT 0,
  verified         INTEGER NOT NULL DEFAULT 0,
  created_at       INTEGER NOT NULL
);
CREATE INDEX idx_otp_phone_time ON otp_requests(phone, created_at);
CREATE INDEX idx_otp_ip_time ON otp_requests(ip, created_at);

-- Short-lived WebAuthn challenges (5 minutes).
CREATE TABLE challenges (
  id          TEXT PRIMARY KEY,
  user_id     TEXT,                            -- set for registration
  challenge   TEXT NOT NULL,
  kind        TEXT NOT NULL,                   -- 'register' | 'login'
  expires_at  INTEGER NOT NULL
);
