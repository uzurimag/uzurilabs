// Minimal client/server-shared validation for the auth forms in this
// ticket. This is NOT the production password policy -- the authoritative
// policy lives in the Supabase project's Auth settings (minimum length,
// leaked-password protection, etc.), which can be stricter than this
// baseline. See docs/auth/ENG-002-authentication-and-sessions.md.
export const MIN_PASSWORD_LENGTH = 8;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function isValidEmail(value: string): boolean {
  return EMAIL_PATTERN.test(value);
}
