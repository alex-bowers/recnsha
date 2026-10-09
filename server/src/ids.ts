const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const ID_LENGTH = 12;
const ID_PATTERN = /^[A-Za-z0-9]{12}$/;
// 248 is the largest multiple of 62 below 256; discarding larger bytes keeps every character equally likely.
const UNBIASED_LIMIT = 248;

export function generateId(): string {
	let id = "";
	while (id.length < ID_LENGTH) {
		for (const byte of crypto.getRandomValues(new Uint8Array(ID_LENGTH * 2))) {
			if (byte < UNBIASED_LIMIT && id.length < ID_LENGTH) {
				id += ALPHABET[byte % ALPHABET.length];
			}
		}
	}
	return id;
}

export function isValidId(value: string): boolean {
	return ID_PATTERN.test(value);
}
