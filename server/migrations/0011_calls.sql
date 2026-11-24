-- 1:1 voice/video calls (signalling only; media goes phone-to-phone, DTLS-SRTP encrypted).
CREATE TABLE calls (
  id          TEXT PRIMARY KEY,
  caller      TEXT NOT NULL,
  callee      TEXT NOT NULL,
  video       INTEGER NOT NULL DEFAULT 0,
  offer       TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'ringing',  -- ringing | answered | ended | rejected | missed
  created_at  INTEGER NOT NULL,
  answered_at INTEGER,
  ended_at    INTEGER
);
CREATE INDEX idx_calls_callee ON calls(callee, created_at);
