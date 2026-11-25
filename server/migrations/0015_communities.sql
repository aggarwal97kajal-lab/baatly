-- Communities: an announcement group (admins post) plus linked groups.
CREATE TABLE communities (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  about       TEXT NOT NULL DEFAULT '',
  creator     TEXT NOT NULL,
  announce_id TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
ALTER TABLE groups ADD COLUMN community_id TEXT;
CREATE INDEX idx_groups_community ON groups(community_id);
