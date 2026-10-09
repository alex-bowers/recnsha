import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { TOKEN } from "./helpers";

describe("plain HTTP", () => {
	it("redirects public requests to HTTPS", async () => {
		const response = await exports.default.fetch("http://share.example.com/AAAAAAAAAAAA.png?x=1", {
			redirect: "manual",
		});
		expect(response.status).toBe(301);
		expect(response.headers.get("Location")).toBe("https://share.example.com/AAAAAAAAAAAA.png?x=1");
	});

	it("refuses API requests instead of redirecting them", async () => {
		const response = await exports.default.fetch("http://share.example.com/api/uploads", {
			headers: { Authorization: `Bearer ${TOKEN}` },
			redirect: "manual",
		});
		expect(response.status).toBe(403);
		expect(await response.json()).toMatchObject({ error: expect.stringContaining("HTTPS is required") });
	});

	it("allows local development over HTTP", async () => {
		const response = await exports.default.fetch("http://localhost:8787/api/uploads", {
			headers: { Authorization: `Bearer ${TOKEN}` },
		});
		expect(response.status).toBe(200);
	});
});
