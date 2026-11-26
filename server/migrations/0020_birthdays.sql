-- Date of birth (YYYY-MM-DD). Only day + month are ever shown to others.
-- birthday_share: 0 everyone, 1 my contacts, 3 nobody.
ALTER TABLE users ADD COLUMN birthday TEXT;
ALTER TABLE users ADD COLUMN birthday_share INTEGER NOT NULL DEFAULT 1;
