# recnsha share server

A Cloudflare Worker that stores screenshots and screen recordings in R2 and serves them at short, unguessable URLs.

## Requirements

- Node.js 22 or later and pnpm 11
- A Cloudflare account with the domain's zone added to it

## Configuration

Your settings live in `wrangler.jsonc`, which is not committed. Create it from the example:

```bash
cp wrangler.example.jsonc wrangler.jsonc
```

Then set your domain in `routes` and `PUBLIC_BASE_URL`, your `database_id` (see [Deployment](#deployment)) and `MAX_STORAGE_GB`. Wrangler commands (`dev`, `deploy`, migrations) use `wrangler.jsonc`. The tests and `pnpm types` use `wrangler.example.jsonc`, so they work on a fresh clone. When you change a setting's structure, update both files.

## Local development

```bash
pnpm install
cp wrangler.example.jsonc wrangler.jsonc
printf 'UPLOAD_TOKEN=local-dev-token\n' > .dev.vars
pnpm exec wrangler d1 migrations apply recnsha --local
pnpm dev
```

Run the tests and type checks:

```bash
pnpm test
pnpm typecheck
```

After changing the bindings or variables in `wrangler.example.jsonc`, regenerate types with `pnpm types`.

## Deployment

1. Sign in: `pnpm exec wrangler login`
2. Create the bucket: `pnpm exec wrangler r2 bucket create recnsha-assets`
3. Create the database: `pnpm exec wrangler d1 create recnsha`, then copy the printed `database_id` into your `wrangler.jsonc` (see [Configuration](#configuration)).
4. Apply migrations: `pnpm exec wrangler d1 migrations apply recnsha --remote`
5. Change `routes` and `PUBLIC_BASE_URL` in `wrangler.jsonc` to your own domain, and set `MAX_STORAGE_GB` (see [Storage limit](#storage-limit)).
6. Deploy: `pnpm run deploy`
7. Generate a token (for example `openssl rand -base64 32`), save it in your password manager, then run `pnpm exec wrangler secret put UPLOAD_TOKEN` and paste it.

To revoke a token, run step 7 again with a new value.

### Updating

When a new migration is added, apply it before deploying:

```bash
pnpm exec wrangler d1 migrations apply recnsha --remote
pnpm run deploy
```

## Storage limit

`MAX_STORAGE_GB` in `wrangler.jsonc` caps everything stored: originals, GIF previews and unfinished multipart uploads. Once a write would pass it, the API returns `507` with `{ "error": "Storage limit of N GB reached. Delete old uploads to free space." }`. If the setting is missing or invalid, uploads fail with `500` rather than being unlimited.

R2 storage beyond the free 10 GB costs about $0.015 per GB per month, so the limit also caps your storage bill (20 GB ≈ $0.15, 50 GB ≈ $0.60 per month).

The total is kept in a one-row `storage_usage` table, updated by database triggers whenever an upload is added, changed or removed, so checking the limit reads one row.

### Abandoned uploads

A multipart upload that is started but never completed, for example because the connection drops or the app quits, stays hidden and keeps counting towards the limit. A daily Cron Trigger (03:00 UTC, set in `wrangler.jsonc`) removes pending uploads started more than 24 hours earlier.

## HTTPS

Plain HTTP is not accepted, except on `localhost` and `127.0.0.1` for `wrangler dev`:

- `/api` requests over HTTP get `403`. If you sent your token over HTTP, replace it.
- Public pages and files over HTTP redirect (`301`) to HTTPS.

## Monitoring and rate limiting

**Usage:** in the Cloudflare dashboard, **Workers & Pages › recnsha** shows requests, errors and CPU time. **Observability** shows the Worker's logs, which are enabled in `wrangler.jsonc`. Unexpected errors are logged with the request method and path, never the token. If you are on the paid Workers plan, add a usage notification under **Notifications** so a spike does not go unnoticed.

**Storage:** to check the total stored:

```bash
pnpm exec wrangler d1 execute recnsha --remote --command "SELECT ROUND(bytes / 1073741824.0, 2) AS gb FROM storage_usage"
```

**Rate limiting:** add one Cloudflare rate-limiting rule so a single IP address cannot flood the share links. Blocked requests never reach the Worker, so they cost nothing. In the dashboard, select the domain, then **Security › Security rules › Create rule › Rate limiting rule**:

| Setting | Value |
|---|---|
| If incoming requests match | URI Path contains `/` (the Free plan can only match on the path, so the rule covers the whole domain) |
| With the same characteristics | IP |
| When rate exceeds | 200 requests per 10 seconds |
| Then take action | Block for 10 seconds |

200 requests per 10 seconds is well above normal use: the Mac app's Library loads up to 40 thumbnails at a time.

## API

All `/api` requests need `Authorization: Bearer <UPLOAD_TOKEN>`. Errors return JSON: `{ "error": "message" }`.

Accepted content types: `image/png`, `image/jpeg`, `image/gif`, `video/mp4`. Request bodies are limited to 50 MiB; use a multipart upload for anything larger.

### Upload object

```json
{
  "id": "AbCdEfGhIjKl",
  "kind": "image",
  "size": 48213,
  "createdAt": 1791460000000,
  "page": "https://share.example.com/AbCdEfGhIjKl",
  "file": "https://share.example.com/AbCdEfGhIjKl.png",
  "gif": null,
  "markdown": "![Screenshot](https://share.example.com/AbCdEfGhIjKl.png)"
}
```

### Endpoints

| Method and path | Body | Success |
|---|---|---|
| `POST /api/uploads` | Raw file; `Content-Type` set to the file type | `201` upload object |
| `GET /api/uploads?limit=20&cursor=N` | – | `200` `{ "uploads": [...], "nextCursor": N or null }`, newest first |
| `DELETE /api/uploads/{id}` | – | `204` |
| `POST /api/uploads/multipart` | `{ "contentType": "video/mp4" }` | `201` `{ "id": "..." }` |
| `PUT /api/uploads/{id}/parts/{n}` | Raw part bytes; `n` from 1 to 10,000 | `200` `{ "partNumber": n, "etag": "..." }` |
| `POST /api/uploads/{id}/complete` | `{ "parts": [{ "partNumber": 1, "etag": "..." }] }` | `200` upload object |
| `PUT /api/uploads/{id}/gif` | Raw GIF; `Content-Type: image/gif`; videos only. Replaces any existing GIF | `200` upload object |

In a multipart upload, every part except the last must be the same size and at least 5 MiB. An upload is not visible publicly until it is complete. Parts count towards the storage limit as they arrive.

Any write can return `507` when the [storage limit](#storage-limit) is reached.

## Public URLs

| URL | Returns |
|---|---|
| `/{id}` | Share page with link-preview tags |
| `/{id}.{ext}` | The original file |
| `/{id}.gif?v={version}` | A video's GIF preview. The API returns this link; `v` changes whenever the GIF is replaced, so it is cached like an original. `/{id}.gif` without `v` also works and is cached for 5 minutes |
