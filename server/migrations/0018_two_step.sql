-- Two-step verification: a 6-digit PIN asked after the SMS code on a new phone.
CREATE TABLE two_step (
  user_id      TEXT PRIMARY KEY,
  hash         TEXT NOT NULL,
  salt         TEXT NOT NULL,
  reset_at     INTEGER,            -- "Forgot PIN": works without PIN after this time (7 days)
  fails        INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER
);

CREATE TABLE pin_tickets (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  device     TEXT NOT NULL DEFAULT '',
  expires_at INTEGER NOT NULL
);
