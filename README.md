#  Record 'n' Share

Self-hosted screenshot and screen recording sharing, in the spirit of Gyazo. A macOS menu-bar app captures an area, a window or a recording and uploads it to your own server. That server, a Cloudflare Worker, stores the file and serves a short share link.

| Part | Folder | Documentation |
|---|---|---|
| Share server (Cloudflare Workers, R2, D1) | `server/` | [server/README.md](server/README.md) |
| macOS app (Swift, SwiftUI) | `mac/` | [mac/README.md](mac/README.md) |

Set up the server first, then the Mac app.

## How it works

1. The Mac app captures a screenshot (PNG) or a recording (MP4) and uploads it with your upload token.
2. The Worker stores the file in a private R2 bucket and its details in a D1 database, then returns a share link such as `https://share.example.com/AbCdEfGhIjKl`.
3. Anyone with the link sees a page with the image or video. Links are random and unlisted, and search engines are asked not to index them.

## Costs

For personal use, the whole setup usually fits within Cloudflare's free allowances. Beyond those:

- **Storage** costs about $0.015 per GB per month after the first 10 GB. The server's `MAX_STORAGE_GB` setting caps it.
- **Downloads** are free.
- **Worker requests:** on the Workers Free plan, requests past the daily allowance fail rather than being billed.

## Security

- Uploading, listing and deleting require the upload token. Viewing requires only the link.
- The server accepts only PNG, JPEG, GIF and MP4 files, refuses API requests over plain HTTP, and caps total storage.
- The Mac app keeps the token in your keychain and uses only HTTPS (plain HTTP is allowed for `localhost` only).
- A Cloudflare rate-limiting rule is recommended; see [server/README.md](server/README.md#monitoring-and-rate-limiting).

## Licence

[MIT](LICENSE)
