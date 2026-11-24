-- Groups. Name/members are visible to the server (like WhatsApp);
-- messages are still end-to-end encrypted for each member.
CREATE TABLE groups (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  about      TEXT NOT NULL DEFAULT '',
  photo      TEXT,
  photo_ver  INTEGER NOT NULL DEFAULT 0,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE group_members (
  group_id TEXT NOT NULL,
  user_id  TEXT NOT NULL,
  role     TEXT NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
  added_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX idx_group_members_user ON group_members(user_id);
