# baatly-api (Cloudflare Worker)

Auth backend: Message Central OTP, passkeys (WebAuthn), device sessions. D1 database `baatly-db`.

- Deploys automatically from `.github/workflows/deploy-server.yml` on push to `main`.
- Secrets (GitHub → Actions): `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, optional `MC_CUSTOMER_ID`, `MC_PASSWORD`.
- Without Message Central secrets the server runs in TEST mode (OTP `123456`).

Local dev: `npm ci && npx wrangler d1 migrations apply baatly-db --local && npx wrangler dev`

