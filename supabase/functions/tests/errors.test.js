import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  badRequest,
  notFound,
  unprocessable,
  publicError,
  GENERIC_MESSAGE,
} from "../_shared/errors.js";

describe("publicError", () => {
  test("passes a deliberate caller-facing error through with its status", () => {
    assert.deepEqual(publicError(badRequest("bad")), { status: 400, message: "bad" });
    assert.deepEqual(publicError(notFound("gone")), { status: 404, message: "gone" });
    assert.deepEqual(publicError(unprocessable("no")), { status: 422, message: "no" });
  });

  test("never leaks an internal error's message", () => {
    const internal = new Error("CJ said: invalid token CJ123@api@secret");
    assert.deepEqual(publicError(internal), { status: 500, message: GENERIC_MESSAGE });
  });
});
