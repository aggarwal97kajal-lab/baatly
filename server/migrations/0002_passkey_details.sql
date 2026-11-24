-- Which authenticator created the passkey (AAGUID) and whether it is synced.
ALTER TABLE passkeys ADD COLUMN aaguid TEXT NOT NULL DEFAULT '';
ALTER TABLE passkeys ADD COLUMN device_type TEXT NOT NULL DEFAULT '';
ALTER TABLE passkeys ADD COLUMN backed_up INTEGER NOT NULL DEFAULT 0;
