-- Muted chats, so the server doesn't send push notifications for them.
CREATE TABLE mutes (
  user_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  until   INTEGER NOT NULL,
  PRIMARY KEY (user_id, peer_id)
);
