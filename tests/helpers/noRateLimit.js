/**
 * Every rate limiter, disabled — for route suites that fire the same endpoint
 * dozens of times and would otherwise trip a real limit partway through.
 *
 * Usage (the require must be INSIDE the factory; jest.mock is hoisted above
 * every import, so a factory cannot close over a module-scope variable):
 *
 *   jest.mock('../../src/middleware/rateLimiter', () => require('../helpers/noRateLimit'));
 *
 * A Proxy rather than a hand-listed object on purpose: the literal versions
 * this replaced named each limiter explicitly, so adding a NEW limiter to
 * src/middleware/rateLimiter.js returned undefined here and every suite that
 * mounts the app died with "argument handler must be a function" — a failure
 * pointing at the new route, miles from the stale mock that actually caused it.
 * Any name, present or future, now resolves to a pass-through.
 *
 * This assumes every export is middleware. globalKey/globalMax are values, not
 * middleware, but nothing outside rateLimiter.js and its own (unmocked) unit
 * test consumes them. Import one into a route and it will need real values here.
 */

const passthrough = (req, res, next) => next();

module.exports = new Proxy({}, {
  get: () => passthrough,
  // jest inspects the module object; without these it reports an empty module.
  has: () => true,
  ownKeys: () => [],
  getOwnPropertyDescriptor: () => ({ configurable: true, enumerable: true }),
});
