/**
 * A minimal stand-in for the supabase-js query builder: every chained
 * filter is recorded, and the awaited result comes from a `respond`
 * callback that sees the whole call. Enough to test the logic around the
 * database (which row a claim targets, what happens when it matches no row)
 * without a live project - the SQL itself is tested in PGlite
 * (supabase/tests/rls.test.mjs).
 */
export function fakeDb(respond) {
  const calls = [];
  const builder = (table) => {
    const call = { table, op: "select", filters: [], payload: undefined };
    calls.push(call);
    const chain = {
      select(columns) {
        call.columns = columns;
        return chain;
      },
      insert(payload) {
        call.op = "insert";
        call.payload = payload;
        return chain;
      },
      update(payload) {
        call.op = "update";
        call.payload = payload;
        return chain;
      },
      upsert(payload) {
        call.op = "upsert";
        call.payload = payload;
        return chain;
      },
      maybeSingle() {
        call.single = true;
        return chain;
      },
      single() {
        call.single = true;
        return chain;
      },
      then(resolve, reject) {
        return Promise.resolve(respond(call)).then(resolve, reject);
      },
    };
    for (const name of ["eq", "in", "is", "or", "order", "limit"]) {
      chain[name] = (...args) => {
        call.filters.push([name, ...args]);
        return chain;
      };
    }
    return chain;
  };
  return {
    calls,
    from: builder,
    rpc: (fn, args) => {
      const call = { rpc: fn, args };
      calls.push(call);
      return Promise.resolve(respond(call));
    },
  };
}
