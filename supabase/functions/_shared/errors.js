/**
 * Errors whose message is safe to show the caller.
 *
 * Anything else thrown inside a handler is an internal failure - a CJ or
 * IntaSend error body, a database error, a stack-adjacent message - and
 * `publicError` replaces it with a generic message, so upstream internals
 * never reach the client. The full error is still logged server-side.
 */
class HttpError extends Error {
  /**
   * @param {number} status HTTP status to respond with.
   * @param {string} message Caller-facing message.
   */
  constructor(status, message) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

/** @param {string} message @return {HttpError} A 400. */
const badRequest = (message) => new HttpError(400, message);
/** @param {string} message @return {HttpError} A 403. */
const forbidden = (message) => new HttpError(403, message);
/** @param {string} message @return {HttpError} A 404. */
const notFound = (message) => new HttpError(404, message);
/**
 * A well-formed request the server can't act on (e.g. no shipping line to
 * that address) - distinct from a malformed one.
 * @param {string} message
 * @return {HttpError} A 422.
 */
const unprocessable = (message) => new HttpError(422, message);

const GENERIC_MESSAGE = "Something went wrong. Please try again.";

/**
 * @param {Error} err Whatever a handler threw.
 * @return {{status: number, message: string}} What to send the caller.
 */
function publicError(err) {
  if (err instanceof HttpError) {
    return { status: err.status, message: err.message };
  }
  return { status: 500, message: GENERIC_MESSAGE };
}

export {
  HttpError,
  badRequest,
  forbidden,
  notFound,
  unprocessable,
  publicError,
  GENERIC_MESSAGE,
};
