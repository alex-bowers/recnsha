import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { BASE_URL, GIF_BYTES, request, uploadImage, uploadVideo, type UploadResponse } from "./helpers";

const JSON_HEADERS = { "Content-Type": "application/json" };

async function startMultipart(contentType = "video/mp4"): Promise<Response> {
	return request("/api/uploads/multipart", {
		method: "POST",
		headers: JSON_HEADERS,
		body: JSON.stringify({ contentType }),
	});
}

describe("multipart uploads", () => {
	it("assembles parts into one file that is hidden until complete", async () => {
		const start = await startMultipart();
		expect(start.status).toBe(201);
		const { id } = await start.json<{ id: string }>();

		const first = new Uint8Array(5 * 1024 * 1024).fill(1);
		const last = new Uint8Array([2, 2, 2]);
		const part1 = await request(`/api/uploads/${id}/parts/1`, { method: "PUT", body: first });
		const part2 = await request(`/api/uploads/${id}/parts/2`, { method: "PUT", body: last });
		expect(part1.status).toBe(200);
		expect(part2.status).toBe(200);

		expect((await request(`/${id}`, {}, null)).status).toBe(404);

		const complete = await request(`/api/uploads/${id}/complete`, {
			method: "POST",
			headers: JSON_HEADERS,
			body: JSON.stringify({ parts: [await part1.json(), await part2.json()] }),
		});
		expect(complete.status).toBe(200);

		const upload = await complete.json<UploadResponse>();
		expect(upload).toMatchObject({
			id,
			kind: "video",
			size: first.byteLength + last.byteLength,
			markdown: `[Recording](${BASE_URL}/${id})`,
		});
		expect((await env.BUCKET.head(`${id}/original.mp4`))?.size).toBe(first.byteLength + last.byteLength);
	});

	it("rejects unsupported content types", async () => {
		expect((await startMultipart("text/html")).status).toBe(415);
	});

	it("rejects invalid part numbers and parts lists", async () => {
		const { id } = await (await startMultipart()).json<{ id: string }>();
		expect((await request(`/api/uploads/${id}/parts/0`, { method: "PUT", body: "x" })).status).toBe(400);
		expect((await request(`/api/uploads/${id}/parts/10001`, { method: "PUT", body: "x" })).status).toBe(400);

		const complete = await request(`/api/uploads/${id}/complete`, {
			method: "POST",
			headers: JSON_HEADERS,
			body: JSON.stringify({ parts: [{ partNumber: "1" }] }),
		});
		expect(complete.status).toBe(400);
	});

	it("refuses parts for uploads that are already complete", async () => {
		const image = await uploadImage();
		expect((await request(`/api/uploads/${image.id}/parts/1`, { method: "PUT", body: "x" })).status).toBe(404);
	});

	it("aborts pending uploads when deleted", async () => {
		const { id } = await (await startMultipart()).json<{ id: string }>();
		expect((await request(`/api/uploads/${id}`, { method: "DELETE" })).status).toBe(204);
	});
});

describe("PUT /api/uploads/:id/gif", () => {
	it("attaches a GIF preview to a video", async () => {
		const upload = await uploadVideo({ withGif: true });
		expect(upload.gif).toMatch(new RegExp(`^${BASE_URL}/${upload.id}\\.gif\\?v=\\d+$`));
		expect(upload.markdown).toBe(`[![Recording](${upload.gif})](${BASE_URL}/${upload.id})`);

		const object = await env.BUCKET.get(`${upload.id}/preview.gif`);
		expect(new Uint8Array(await object!.arrayBuffer())).toEqual(GIF_BYTES);
	});

	it("replaces an existing GIF when a new segment is uploaded", async () => {
		const upload = await uploadVideo({ withGif: true });
		const replacement = new TextEncoder().encode("GIF89a-second-segment");

		const response = await request(`/api/uploads/${upload.id}/gif`, {
			method: "PUT",
			headers: { "Content-Type": "image/gif" },
			body: replacement,
		});
		expect(response.status).toBe(200);
		// A new version gives the GIF a new URL, so caches fetch the replacement.
		expect((await response.json<UploadResponse>()).gif).not.toBe(upload.gif);

		const object = await env.BUCKET.get(`${upload.id}/preview.gif`);
		expect(new Uint8Array(await object!.arrayBuffer())).toEqual(replacement);
	});

	it("only accepts GIFs for videos", async () => {
		const video = await uploadVideo({ withGif: false });
		const wrongType = await request(`/api/uploads/${video.id}/gif`, {
			method: "PUT",
			headers: { "Content-Type": "image/png" },
			body: GIF_BYTES,
		});
		expect(wrongType.status).toBe(415);

		const image = await uploadImage();
		const notVideo = await request(`/api/uploads/${image.id}/gif`, {
			method: "PUT",
			headers: { "Content-Type": "image/gif" },
			body: GIF_BYTES,
		});
		expect(notVideo.status).toBe(404);
	});
});
