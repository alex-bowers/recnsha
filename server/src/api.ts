import { isAuthorised } from "./auth";
import { errorResponse, json, readBody, readJson } from "./http";
import { generateId, isValidId } from "./ids";
import { buildLinks } from "./links";
import { mediaTypeFor, type MediaType } from "./media";
import { discardUpload } from "./cleanup";
import { checkQuota } from "./quota";
import {
	addPendingBytes,
	findUpload,
	gifKey,
	insertUpload,
	listReadyUploads,
	markHasGif,
	markReady,
	originalKey,
	type StoredUpload,
	type Upload,
} from "./uploads";

// Cloudflare rejects request bodies over 100 MB and Workers have 128 MB of memory.
export const MAX_BODY_BYTES = 50 * 1024 * 1024;
const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;
const MAX_PART_NUMBER = 10_000;

export async function handleApi(request: Request, env: Env, url: URL): Promise<Response> {
	if (!(await isAuthorised(request, env.UPLOAD_TOKEN))) return errorResponse("Unauthorised", 401);

	const segments = url.pathname.split("/").filter(Boolean);
	if (segments[1] !== "uploads") return errorResponse("Not found", 404);
	const [, , id, action, partNumber] = segments;
	const method = request.method;

	if (segments.length === 2 && method === "POST") return createUpload(request, env);
	if (segments.length === 2 && method === "GET") return listUploads(env, url);
	if (segments.length === 3 && id === "multipart" && method === "POST") return startMultipart(request, env);
	if (segments.length < 3 || !isValidId(id)) return errorResponse("Not found", 404);
	if (segments.length === 3 && method === "DELETE") return removeUpload(env, id);
	if (segments.length === 4 && action === "gif" && method === "PUT") return putGif(request, env, id);
	if (segments.length === 4 && action === "complete" && method === "POST") return completeMultipart(request, env, id);
	if (segments.length === 5 && action === "parts" && method === "PUT") return uploadPart(request, env, id, partNumber);
	return errorResponse("Not found", 404);
}

export function present(upload: Upload, env: Env) {
	return {
		id: upload.id,
		kind: upload.kind,
		size: upload.size,
		createdAt: upload.createdAt,
		...buildLinks(upload, env.PUBLIC_BASE_URL),
	};
}

export function newUpload(media: MediaType, size: number): Upload {
	return {
		id: generateId(),
		kind: media.kind,
		contentType: media.contentType,
		extension: media.extension,
		size,
		hasGif: false,
		createdAt: Date.now(),
	};
}

async function createUpload(request: Request, env: Env): Promise<Response> {
	const media = mediaTypeFor(request.headers.get("Content-Type"));
	if (media === null) return errorResponse("Unsupported content type", 415);

	const body = await readBody(request, MAX_BODY_BYTES);
	if (body instanceof Response) return body;
	const quotaError = await checkQuota(env, body.byteLength);
	if (quotaError) return quotaError;

	const upload = newUpload(media, body.byteLength);
	await env.BUCKET.put(originalKey(upload), body, { httpMetadata: { contentType: upload.contentType } });
	await insertUpload(env.DB, upload, "ready");
	return json(present(upload, env), 201);
}

async function listUploads(env: Env, url: URL): Promise<Response> {
	const limit = Number(url.searchParams.get("limit") ?? DEFAULT_PAGE_SIZE);
	const cursorParam = url.searchParams.get("cursor");
	const cursor = cursorParam === null ? null : Number(cursorParam);
	if (!Number.isInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE) {
		return errorResponse(`limit must be between 1 and ${MAX_PAGE_SIZE}`, 400);
	}
	if (cursor !== null && !Number.isSafeInteger(cursor)) return errorResponse("cursor must be an integer", 400);

	const uploads = await listReadyUploads(env.DB, cursor, limit);
	const last = uploads.at(-1);
	return json({
		uploads: uploads.map((upload) => present(upload, env)),
		nextCursor: uploads.length === limit && last ? last.cursor : null,
	});
}

async function removeUpload(env: Env, id: string): Promise<Response> {
	const upload = await findUpload(env.DB, id);
	if (upload === null) return errorResponse("Not found", 404);

	await discardUpload(env, upload);
	return new Response(null, { status: 204 });
}

async function startMultipart(request: Request, env: Env): Promise<Response> {
	const payload = await readJson(request);
	const media = typeof payload?.contentType === "string" ? mediaTypeFor(payload.contentType) : null;
	if (media === null) return errorResponse("Unsupported content type", 415);
	// The upload brings no bytes yet, but there must be room for at least one.
	const quotaError = await checkQuota(env, 1);
	if (quotaError) return quotaError;

	const upload = newUpload(media, 0);
	const multipart = await env.BUCKET.createMultipartUpload(originalKey(upload), {
		httpMetadata: { contentType: upload.contentType },
	});
	await insertUpload(env.DB, upload, "pending", multipart.uploadId);
	return json({ id: upload.id }, 201);
}

async function findPending(env: Env, id: string): Promise<(StoredUpload & { multipartUploadId: string }) | null> {
	const upload = await findUpload(env.DB, id);
	if (upload === null || upload.status !== "pending" || upload.multipartUploadId === null) return null;
	return { ...upload, multipartUploadId: upload.multipartUploadId };
}

async function uploadPart(request: Request, env: Env, id: string, partNumberText: string): Promise<Response> {
	const partNumber = Number(partNumberText);
	if (!Number.isInteger(partNumber) || partNumber < 1 || partNumber > MAX_PART_NUMBER) {
		return errorResponse(`Part number must be between 1 and ${MAX_PART_NUMBER}`, 400);
	}

	const upload = await findPending(env, id);
	if (upload === null) return errorResponse("Not found", 404);

	const body = await readBody(request, MAX_BODY_BYTES);
	if (body instanceof Response) return body;
	const quotaError = await checkQuota(env, body.byteLength);
	if (quotaError) return quotaError;

	const multipart = env.BUCKET.resumeMultipartUpload(originalKey(upload), upload.multipartUploadId);
	const part = await multipart.uploadPart(partNumber, body);
	await addPendingBytes(env.DB, id, body.byteLength);
	return json({ partNumber: part.partNumber, etag: part.etag });
}

function parseParts(value: unknown): R2UploadedPart[] | null {
	if (!Array.isArray(value) || value.length === 0) return null;
	const parts: R2UploadedPart[] = [];
	for (const item of value) {
		if (typeof item !== "object" || item === null) return null;
		const { partNumber, etag } = item as Record<string, unknown>;
		if (typeof partNumber !== "number" || !Number.isInteger(partNumber) || typeof etag !== "string") return null;
		parts.push({ partNumber, etag });
	}
	return parts;
}

async function completeMultipart(request: Request, env: Env, id: string): Promise<Response> {
	const upload = await findPending(env, id);
	if (upload === null) return errorResponse("Not found", 404);

	const parts = parseParts((await readJson(request))?.parts);
	if (parts === null) return errorResponse("parts must be a list of { partNumber, etag }", 400);

	const multipart = env.BUCKET.resumeMultipartUpload(originalKey(upload), upload.multipartUploadId);
	const object = await multipart.complete(parts);
	await markReady(env.DB, id, object.size);
	return json(present({ ...upload, size: object.size }, env));
}

async function putGif(request: Request, env: Env, id: string): Promise<Response> {
	if (mediaTypeFor(request.headers.get("Content-Type"))?.contentType !== "image/gif") {
		return errorResponse("GIF previews must be image/gif", 415);
	}

	const upload = await findUpload(env.DB, id);
	if (upload === null || upload.status !== "ready" || upload.kind !== "video") return errorResponse("Not found", 404);

	const body = await readBody(request, MAX_BODY_BYTES);
	if (body instanceof Response) return body;
	// A replacement GIF only adds the difference from the one it replaces.
	const quotaError = await checkQuota(env, body.byteLength - upload.gifSize);
	if (quotaError) return quotaError;

	await env.BUCKET.put(gifKey(id), body, { httpMetadata: { contentType: "image/gif" } });
	const gifVersion = Date.now();
	await markHasGif(env.DB, id, body.byteLength, gifVersion);
	return json(present({ ...upload, hasGif: true, gifVersion }, env));
}
