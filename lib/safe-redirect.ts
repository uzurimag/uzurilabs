/**
 * Only ever returns a same-origin, relative path. Used to validate `next`/
 * `return` query params before redirecting, so a crafted link can't send a
 * signed-in user to an attacker-controlled URL (open redirect).
 */
export function getSafeRedirectPath(
  value: string | null | undefined,
  fallback: string,
): string {
  if (!value) {
    return fallback;
  }

  // Must start with a single "/" (relative path), not "//" or "/\" which
  // browsers can interpret as protocol-relative URLs to another host, and
  // must not contain a scheme ("javascript:", "https://", etc.).
  if (!/^\/(?!\/|\\)/.test(value) || value.includes("://")) {
    return fallback;
  }

  return value;
}
