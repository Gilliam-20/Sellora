/**
 * Reads an environment variable - a Supabase Edge Function secret
 * (`supabase secrets set NAME=value`) or one of the variables the runtime
 * injects itself (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY).
 * @param {string} name Variable name.
 * @return {string|undefined} Its value, or undefined when unset.
 */
export function env(name) {
  return globalThis.Deno?.env.get(name) ?? undefined;
}

/**
 * Like `env`, but a missing value is a deployment mistake, not a runtime
 * condition - fail loudly with the name so the fix is obvious from the log.
 * @param {string} name Variable name.
 * @return {string} Its value.
 */
export function requireEnv(name) {
  const value = env(name);
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}
