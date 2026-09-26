/**
 * Epoch milliseconds for a stored timestamp.
 *
 * Postgres hands timestamptz columns back as ISO strings; tests and freshly
 * built rows use Dates or numbers. Anything unreadable is 0 ("long ago"),
 * which is what every caller wants: a missing claim time must read as
 * stale, never as live.
 * @param {*} value ISO string, Date, epoch ms, or null.
 * @return {number} Epoch ms, or 0 when there's no usable timestamp.
 */
export function millisOf(value) {
  if (value == null || value === "") return 0;
  if (value instanceof Date) return value.getTime() || 0;
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : 0;
}
