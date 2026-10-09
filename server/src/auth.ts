const encoder = new TextEncoder();

/** Checks the bearer token in constant time. Fails closed if the secret is not configured. */
export async function isAuthorised(request: Request, token: string | undefined): Promise<boolean> {
	const header = request.headers.get("Authorization") ?? "";
	if (!token || !header.startsWith("Bearer ")) return false;

	// Hashing first gives both values the same length, which timingSafeEqual requires.
	const [given, expected] = await Promise.all([
		crypto.subtle.digest("SHA-256", encoder.encode(header.slice("Bearer ".length))),
		crypto.subtle.digest("SHA-256", encoder.encode(token)),
	]);
	return crypto.subtle.timingSafeEqual(given, expected);
}
