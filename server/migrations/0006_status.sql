-- Status updates. The body is encrypted on the phone with a random key;
-- that key is sealed separately for each person allowed to see it.
CREATE TABLE statuses (
  id          TEXT PRIMARY KEY,
  owner_id    TEXT NOT NULL,
  body        TEXT NOT NULL,           -- base64 ciphertext (photo/text)
  allow_share INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX idx_status_owner ON statuses(owner_id, created_at);
CREATE INDEX idx_status_expiry ON statuses(expires_at);

CREATE TABLE status_keys (
  status_id TEXT NOT NULL,
  viewer_id TEXT NOT NULL,
  sealed    TEXT NOT NULL,             -- content key, end-to-end encrypted for this viewer
  PRIMARY KEY (status_id, viewer_id)
);
CREATE INDEX idx_status_keys_viewer ON status_keys(viewer_id);

CREATE TABLE status_views (
  status_id TEXT NOT NULL,
  viewer_id TEXT NOT NULL,
  at        INTEGER NOT NULL,
  PRIMARY KEY (status_id, viewer_id)
);
