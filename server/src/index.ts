import { handleApi } from "./api";
import { cleanUpAbandonedUploads } from "./cleanup";
import { serveFile } from "./files";
import { errorResponse, notFound } from "./http";
import { isValidId } from "./ids";
import { renderPage } from "./page";
import { findUpload } from "./uploads";

// "/{id}" or "/{id}.{ext}". Anything with more dots or slashes is rejected.
const PUBLIC_PATH = /^\/([^/.]+)(?:\.([a-z0-9]+))?$/;
// `wrangler dev` serves plain HTTP on these hosts.
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1"]);

export default {
	async fetch(request, env): Promise<Response> {
		const url = new URL(request.url);
		let response: Response;
		try {
			if (url.protocol === "http:" && !LOCAL_HOSTS.has(url.hostname)) {
				response = rejectPlainHttp(url);
			} else if (url.pathname.startsWith("/api/")) {
				response = await handleApi(request, env, url);
			} else {
				response = await handlePublic(request, env, url);
			}
		} catch (error) {
			console.error("Unhandled error", request.method, url.pathname, error);
			response = errorResponse("Internal error", 500);
		}
		response.headers.set("X-Content-Type-Options", "nosniff");
		response.headers.set("X-Robots-Tag", "noindex");
		return response;
	},

	/** Daily Cron Trigger (see wrangler.jsonc). */
	async scheduled(controller, env) {
		const removed = await cleanUpAbandonedUploads(env, controller.scheduledTime);
		if (removed > 0) console.log("Removed abandoned uploads", removed);
	},
} satisfies ExportedHandler<Env>;

/**
 * API requests are refused rather than redirected: the token has already crossed the network
 * unencrypted, and a redirect would make the client send it again.
 */
function rejectPlainHttp(url: URL): Response {
	if (url.pathname.startsWith("/api/")) {
		return errorResponse("HTTPS is required. If you sent your upload token over HTTP, replace it.", 403);
	}
	return new Response(null, { status: 301, headers: { Location: `https://${url.host}${url.pathname}${url.search}` } });
}

async function handlePublic(request: Request, env: Env, url: URL): Promise<Response> {
	if (request.method !== "GET" && request.method !== "HEAD") {
		return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
	}

	const match = PUBLIC_PATH.exec(url.pathname);
	if (match === null || !isValidId(match[1])) return notFound();

	const upload = await findUpload(env.DB, match[1]);
	if (upload === null || upload.status !== "ready") return notFound();

	const extension: string | undefined = match[2];
	return extension === undefined ? renderPage(upload, env.PUBLIC_BASE_URL) : serveFile(request, env, upload, extension);
}
