// Entrypoint of the `api` Edge Function. The routing and every endpoint live
// in handler.ts, which the tests import directly without starting a server.

import { handle } from "./handler.ts";

Deno.serve(handle);
