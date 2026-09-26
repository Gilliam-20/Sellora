import { createClient } from "npm:@supabase/supabase-js@2";
import { requireEnv } from "./env.js";

/**
 * The service-role Supabase client. It bypasses RLS - the same trust the
 * Firebase Admin SDK had - so it lives only here, server-side, and every
 * handler that uses it on a caller's behalf checks ownership itself first.
 *
 * Created lazily so tests can swap in a fake before anything connects.
 */
let client = null;

/** @return {import("npm:@supabase/supabase-js@2").SupabaseClient} The shared service-role client. */
export function db() {
  client ??= createClient(
      requireEnv("SUPABASE_URL"),
      requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
  );
  return client;
}

/**
 * Replaces the shared client. For tests.
 * @param {object|null} next A fake with the supabase-js surface used here.
 */
export function setDb(next) {
  client = next;
}

/**
 * Unwraps a supabase-js result, turning `{ error }` into a thrown Error so
 * handlers can use plain try/catch the way they did with Firestore. The
 * message stays internal - `errors.publicError` never forwards it.
 * @param {{data: *, error: (object|null)}} result A supabase-js response.
 * @return {*} `result.data`.
 */
export function must({ data, error }) {
  if (error) {
    const err = new Error(`Database error ${error.code || ""}: ${error.message}`);
    err.cause = error;
    throw err;
  }
  return data;
}
