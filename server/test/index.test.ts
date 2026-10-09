import { exports } from "cloudflare:workers";
import { expect, it } from "vitest";

it("returns 404 for the root path", async () => {
	const response = await exports.default.fetch("https://share.example.com/");
	expect(response.status).toBe(404);
});
