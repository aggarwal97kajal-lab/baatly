-- Encrypted chat media stored in R2 (photos, voice notes, documents).
-- Only ciphertext is stored; the key travels inside the E2E message.
CREATE TABLE media (
  id         TEXT PRIMARY KEY,
  owner_id   TEXT NOT NULL,
  size       INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_media_created ON media(created_at);
