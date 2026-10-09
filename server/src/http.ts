export function json(body: unknown, status = 200): Response {
	return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export function errorResponse(message: string, status: number): Response {
	return json({ error: message }, status);
}

export function notFound(): Response {
	return new Response("Not found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

/** Reads a non-empty request body up to `maxBytes`. Returns an error response if it is empty or too large. */
export async function readBody(request: Request, maxBytes: number): Promise<ArrayBuffer | Response> {
	const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
	if (declaredLength > maxBytes) return errorResponse(`Body exceeds ${maxBytes} bytes`, 413);

	const body = await request.arrayBuffer();
	if (body.byteLength === 0) return errorResponse("Body is empty", 400);
	if (body.byteLength > maxBytes) return errorResponse(`Body exceeds ${maxBytes} bytes`, 413);
	return body;
}

/** Parses a JSON object body. Returns null for invalid JSON or non-object values. */
export async function readJson(request: Request): Promise<Record<string, unknown> | null> {
	try {
		const value: unknown = await request.json();
		return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
	} catch {
		return null;
	}
}
