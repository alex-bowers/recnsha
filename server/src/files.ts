import { notFound } from "./http";
import { gifKey, originalKey, type Upload } from "./uploads";

// IDs are never reused, so an original file at a given URL never changes.
const IMMUTABLE = "public, max-age=31536000, immutable";
// A video's GIF can be replaced with a different segment, so caches must refresh it.
const REPLACEABLE = "public, max-age=300";

export async function serveFile(request: Request, env: Env, upload: Upload, extension: string): Promise<Response> {
	const key = keyFor(upload, extension);
	if (key === null) return notFound();

	let object: R2Object | R2ObjectBody | null;
	try {
		object = await env.BUCKET.get(key, { range: request.headers, onlyIf: request.headers });
	} catch (error) {
		// R2 rejects ranges it cannot satisfy.
		if (!request.headers.has("Range")) throw error;
		return rangeNotSatisfiable(env, key);
	}
	if (object === null) return notFound();

	const headers = new Headers();
	object.writeHttpMetadata(headers);
	headers.set("ETag", object.httpEtag);
	// A versioned GIF URL (?v=) never changes; an unversioned one may be replaced.
	const replaceable = key === gifKey(upload.id) && !new URL(request.url).searchParams.has("v");
	headers.set("Cache-Control", replaceable ? REPLACEABLE : IMMUTABLE);
	headers.set("Accept-Ranges", "bytes");

	// R2 omits the body when a precondition stops it sending one.
	if (!("body" in object)) {
		const isRevalidation = request.headers.has("If-None-Match") || request.headers.has("If-Modified-Since");
		return new Response(null, { status: isRevalidation ? 304 : 412, headers });
	}

	const rangeHeader = request.headers.get("Range");
	if (rangeHeader !== null && object.range) {
		// Some R2 versions return the whole object for a range starting past the end instead of failing.
		if (requestedStart(rangeHeader) >= object.size) {
			await object.body.cancel();
			return rangeNotSatisfiable(env, key);
		}
		const { start, end } = byteRange(object.range, object.size);
		headers.set("Content-Range", `bytes ${start}-${end}/${object.size}`);
		return new Response(object.body, { status: 206, headers });
	}
	return new Response(object.body, { headers });
}

async function rangeNotSatisfiable(env: Env, key: string): Promise<Response> {
	const head = await env.BUCKET.head(key);
	if (head === null) return notFound();
	return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${head.size}` } });
}

/** The first byte of a "bytes=N-" or "bytes=N-M" range, or 0 for suffix ranges and anything else. */
function requestedStart(rangeHeader: string): number {
	const match = /^bytes=(\d+)-/.exec(rangeHeader.trim());
	return match ? Number(match[1]) : 0;
}

function keyFor(upload: Upload, extension: string): string | null {
	if (extension === upload.extension) return originalKey(upload);
	if (extension === "gif" && upload.kind === "video" && upload.hasGif) return gifKey(upload.id);
	return null;
}

function byteRange(range: R2Range, size: number): { start: number; end: number } {
	// R2 can include `suffix: undefined` on offset ranges, so check values rather than which keys exist.
	const { offset, length, suffix } = range as { offset?: number; length?: number; suffix?: number };
	if (suffix !== undefined) {
		return { start: Math.max(size - suffix, 0), end: size - 1 };
	}
	const start = offset ?? 0;
	return { start, end: start + (length ?? size - start) - 1 };
}
