const client = require('prom-client');
const User = require('./models/User.model');

// Create a gauge to track the total number of users.
const userCountGauge = new client.Gauge({
  name: 'users_total',
  help: 'Total number of users',
});

// Function to query and update user count
async function updateUserCount() {
  try {
    const count = await User.countDocuments();
    userCountGauge.set(count);
  } catch (error) {
    console.error('Error updating user count:', error);
  }
}

// Start periodic updates (e.g., every minute)
const UPDATE_INTERVAL_MS = 60000; // one minute
setInterval(updateUserCount, UPDATE_INTERVAL_MS);

updateUserCount();

// Overall HTTP requests counter without labels.
const totalHttpRequestsCounter = new client.Counter({
  name: 'http_requests_overall_total',
  help: 'Overall total number of HTTP requests',
});

// Counter with labels for detailed HTTP request tracking.
const httpRequestsCounter = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests with labels',
  labelNames: ['method', 'route', 'statusCode'],
});

// How long each request takes, for the latency panels (p95 per service).
// Labels: method and route only. Each label multiplies the number of series by
// its number of values, and a histogram already has one series per bucket.
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Time from request to response, in seconds',
  labelNames: ['method', 'route'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 10],
});

// The "route" label is the route pattern from the code, such as
// /api/items/items/:id, never the URL the visitor sent. Every different label
// value is a new time series in Prometheus's memory: with the raw URL, each
// made-up URL created one more, and junk requests could crash the monitoring
// (finding F18). Now the number of values is fixed by the code. Requests that
// match no route, such as junk URLs or a refused login token, count as "no_route".
//
// Express forgets the first part of the path (req.baseUrl) when an error or a
// refused token leaves a router. So the pattern is noted at the moment Express
// picks the route, not when the response is sent.
function routePattern(req) {
  let route;
  let pattern = 'no_route';
  Object.defineProperty(req, 'route', {
    configurable: true,
    enumerable: true,
    get() { return route; },
    set(value) {
      route = value;
      pattern = req.baseUrl + value.path;
    },
  });
  return () => pattern;
}

// Express middleware to update both HTTP requests counters.
function httpMetricsMiddleware(req, res, next) {
  const pattern = routePattern(req);
  const endTimer = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const method = req.method;
    const route = pattern();
    const statusCode = res.statusCode.toString();

    // Increment the detailed counter.
    httpRequestsCounter.labels(method, route, statusCode).inc();
    endTimer({ method, route });

    // Increment the overall counter.
    totalHttpRequestsCounter.inc();
  });
  next();
}

module.exports = {
  httpMetricsMiddleware,
};