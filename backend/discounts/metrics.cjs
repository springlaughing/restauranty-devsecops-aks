// metrics.js
const client = require('prom-client');
const Campaigns = require('./models/campaigns.model');
const Coupons = require('./models/coupons.model');

// Create a gauge to track the total number of campaigns.
const campaignsCountGauge = new client.Gauge({
  name: 'campaigns_total',
  help: 'Total number of campaigns',
});

// Create a gauge to track the total number of coupons.
const couponsCountGauge = new client.Gauge({
  name: 'coupons_total',
  help: 'Total number of coupons',
});

// Function to query and update user count
async function updateCampaignsCount() {
  try {
    const count = await Campaigns.countDocuments();
    campaignsCountGauge.set(count);
  } catch (error) {
    console.error('Error updating campaigns count:', error);
  }
}

// Function to query and update coupons count
async function updateCouponsCount() {
  try {
    const count = await Coupons.countDocuments();
    couponsCountGauge.set(count);
  } catch (error) {
    console.error('Error updating coupons count:', error);
  }
}

// Start periodic updates (e.g., every minute)
const UPDATE_INTERVAL_MS = 60000; // one minute
setInterval(updateCampaignsCount, UPDATE_INTERVAL_MS);
setInterval(updateCouponsCount, UPDATE_INTERVAL_MS);

updateCampaignsCount();
updateCouponsCount();

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
  res.on('finish', () => {
    const method = req.method;
    const route = pattern();
    const statusCode = res.statusCode.toString();

    // Increment the detailed counter.
    httpRequestsCounter.labels(method, route, statusCode).inc();

    // Increment the overall counter.
    totalHttpRequestsCounter.inc();
  });
  next();
}

module.exports = {
  httpMetricsMiddleware,
};