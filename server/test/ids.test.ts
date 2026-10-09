import { describe, expect, it } from "vitest";
import { generateId, isValidId } from "../src/ids";

describe("generateId", () => {
	it("creates 12-character alphanumeric IDs", () => {
		for (let i = 0; i < 1000; i++) {
			expect(generateId()).toMatch(/^[A-Za-z0-9]{12}$/);
		}
	});

	it("does not repeat", () => {
		const ids = new Set(Array.from({ length: 1000 }, () => generateId()));
		expect(ids.size).toBe(1000);
	});
});

describe("isValidId", () => {
	it("accepts generated IDs", () => {
		expect(isValidId(generateId())).toBe(true);
	});

	it("rejects anything else", () => {
		for (const value of ["", "short", "abcdefghijk!", "abcdefghijklm", "../etc/passwd"]) {
			expect(isValidId(value)).toBe(false);
		}
	});
});
