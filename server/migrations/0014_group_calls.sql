-- Group voice/video calls (mesh: every phone connects to every other phone).
CREATE TABLE group_calls (
  id         TEXT PRIMARY KEY,
  group_id   TEXT NOT NULL,
  creator    TEXT NOT NULL,
  video      INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  ended_at   INTEGER
);
CREATE INDEX idx_gcalls_group ON group_calls(group_id, created_at);

CREATE TABLE group_call_members (
  call_id   TEXT NOT NULL,
  user_id   TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  left_at   INTEGER,
  PRIMARY KEY (call_id, user_id)
);
