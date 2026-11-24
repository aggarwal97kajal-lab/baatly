-- Privacy settings (JSON), profile photo, and which BAATLY users are in
-- each user's phone book (only matched BAATLY ids; the phone book itself
-- is never stored). Needed to enforce "My contacts" privacy options.
ALTER TABLE users ADD COLUMN privacy TEXT NOT NULL DEFAULT '{}';
ALTER TABLE users ADD COLUMN photo TEXT;
ALTER TABLE users ADD COLUMN photo_ver INTEGER NOT NULL DEFAULT 0;

CREATE TABLE user_contacts (
  user_id    TEXT NOT NULL,
  contact_id TEXT NOT NULL,
  PRIMARY KEY (user_id, contact_id)
);
