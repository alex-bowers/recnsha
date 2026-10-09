// Secrets are not in wrangler.jsonc, so `wrangler types` cannot see them.
interface Env {
	UPLOAD_TOKEN: string;
}
