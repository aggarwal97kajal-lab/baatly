-- In-app "Contact us" messages (also emailed to the team when email is set up).
CREATE TABLE support_tickets (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  kind       TEXT NOT NULL,
  text       TEXT NOT NULL,
  device     TEXT NOT NULL DEFAULT '',
  shots      INTEGER NOT NULL DEFAULT 0,
  emailed    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
