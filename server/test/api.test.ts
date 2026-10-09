import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { BASE_URL, PNG_BYTES, request, uploadImage, type ListResponse, type UploadResponse } from "./helpers";

describe("authentication", () => {
	it("rejects requests without a token", async () => {
		const response = await request("/api/uploads", {}, null);
		expect(response.status).toBe(401);
	});

	it("rejects requests with the wrong token", async () => {
		const response = await request("/api/uploads", {}, "wrong-token");
		expect(response.status).toBe(401);
	});
});

describe("POST /api/uploads", () => {
	it("stores an image and returns its links", async () => {
		const response = await request("/api/uploads", {
			method: "POST",
			headers: { "Content-Type": "image/png" },
			body: PNG_BYTES,
		});
		expect(response.status).toBe(201);

		const upload = await response.json<UploadResponse>();
		expect(upload.id).toMatch(/^[A-Za-z0-9]{12}$/);
		expect(upload).toMatchObject({
			kind: "image",
			size: PNG_BYTES.byteLength,
			page: `${BASE_URL}/${upload.id}`,
			file: `${BASE_URL}/${upload.id}.png`,
			gif: null,
			markdown: `![Screenshot](${BASE_URL}/${upload.id}.png)`,
		});

		const object = await env.BUCKET.get(`${upload.id}/original.png`);
		expect(object?.httpMetadata?.contentType).toBe("image/png");
		expect(new Uint8Array(await object!.arrayBuffer())).toEqual(PNG_BYTES);
	});

	it("rejects unsupported content types", async () => {
		const response = await request("/api/uploads", {
			method: "POST",
			headers: { "Content-Type": "text/html" },
			body: "<script>alert(1)</script>",
		});
		expect(response.status).toBe(415);
	});

	it("rejects empty bodies", async () => {
		const response = await request("/api/uploads", {
			method: "POST",
			headers: { "Content-Type": "image/png" },
			body: new Uint8Array(),
		});
		expect(response.status).toBe(400);
	});
});

describe("GET /api/uploads", () => {
	it("lists uploads newest first with a cursor", async () => {
		const older = await uploadImage();
		const newer = await uploadImage();

		const first = await (await request("/api/uploads?limit=1")).json<ListResponse>();
		expect(first.uploads.map((upload) => upload.id)).toEqual([newer.id]);
		expect(first.nextCursor).not.toBeNull();

		const second = await (await request(`/api/uploads?limit=1&cursor=${first.nextCursor}`)).json<ListResponse>();
		expect(second.uploads.map((upload) => upload.id)).toEqual([older.id]);
	});

	it("rejects invalid pagination", async () => {
		expect((await request("/api/uploads?limit=0")).status).toBe(400);
		expect((await request("/api/uploads?limit=101")).status).toBe(400);
		expect((await request("/api/uploads?cursor=abc")).status).toBe(400);
	});
});

describe("DELETE /api/uploads/:id", () => {
	it("removes the record and the stored file", async () => {
		const upload = await uploadImage();

		const response = await request(`/api/uploads/${upload.id}`, { method: "DELETE" });
		expect(response.status).toBe(204);
		expect(await env.BUCKET.head(`${upload.id}/original.png`)).toBeNull();

		const again = await request(`/api/uploads/${upload.id}`, { method: "DELETE" });
		expect(again.status).toBe(404);
	});
});

it("returns 404 for unknown API routes", async () => {
	expect((await request("/api/unknown")).status).toBe(404);
	expect((await request("/api/uploads/not-an-id", { method: "DELETE" })).status).toBe(404);
});
