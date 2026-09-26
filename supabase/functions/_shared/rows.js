/**
 * Row <-> object key translation, the server-side twin of toRow/fromRow in
 * lib/data/services/supabase_service.dart: columns are snake_case, the
 * ported logic (and every JSON response the app reads) is camelCase. Only
 * the top level is translated - jsonb values (items, tracking, payment_ref,
 * ...) keep their camelCase keys, exactly as the app writes them.
 */

const snake = (key) => key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
const camel = (column) => column.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());

/**
 * @param {object} object camelCase fields.
 * @return {object} The same values under snake_case column names, with
 *   `undefined` fields dropped (so a partial update leaves them alone).
 */
export function toRow(object) {
  const row = {};
  for (const [key, value] of Object.entries(object || {})) {
    if (value !== undefined) row[snake(key)] = value;
  }
  return row;
}

/**
 * @param {object|null} row A row as supabase-js returns it.
 * @return {object|null} The same values under camelCase keys.
 */
export function fromRow(row) {
  if (!row) return row;
  const object = {};
  for (const [key, value] of Object.entries(row)) object[camel(key)] = value;
  return object;
}
