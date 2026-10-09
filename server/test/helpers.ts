import { exports } from "cloudflare:workers";

export const BASE_URL = "https://share.example.com";
export const TOKEN = "test-token";
export const PNG_BYTES = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);

export interface UploadResponse {
	id: string;
	kind: "image" | "video";
	size: number;
	createdAt: number;
	page: string;
	file: string;
	gif: string | null;
	markdown: string;
}

export interface ListResponse {
	uploads: UploadResponse[];
	nextCursor: number | null;
}

/** Sends a request to the Worker. Pass `token: null` for an unauthenticated (public) request. */
export function request(path: string, init: RequestInit = {}, token: string | null = TOKEN): Promise<Response> {
	const headers = new Headers(init.headers);
	if (token !== null) headers.set("Authorization", `Bearer ${token}`);
	return exports.default.fetch(`${BASE_URL}${path}`, { ...init, headers });
}

export async function uploadImage(): Promise<UploadResponse> {
	const response = await request("/api/uploads", {
		method: "POST",
		headers: { "Content-Type": "image/png" },
		body: PNG_BYTES,
	});
	if (response.status !== 201) throw new Error(`Upload failed with ${response.status}`);
	return response.json<UploadResponse>();
}

export const GIF_BYTES = new TextEncoder().encode("GIF89a-test");
export const MP4_BYTES = new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 1, 2, 3, 4]);

export async function uploadVideo({ withGif }: { withGif: boolean }): Promise<UploadResponse> {
	const response = await request("/api/uploads", {
		method: "POST",
		headers: { "Content-Type": "video/mp4" },
		body: MP4_BYTES,
	});
	if (response.status !== 201) throw new Error(`Upload failed with ${response.status}`);
	const upload = await response.json<UploadResponse>();
	if (!withGif) return upload;

	const gif = await request(`/api/uploads/${upload.id}/gif`, {
		method: "PUT",
		headers: { "Content-Type": "image/gif" },
		body: GIF_BYTES,
	});
	if (gif.status !== 200) throw new Error(`GIF upload failed with ${gif.status}`);
	return gif.json<UploadResponse>();
}
