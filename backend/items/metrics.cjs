// metrics.js
const client = require('prom-client');
const Dietary = require('./models/dietary.model');
const Item = require('./models/Item.model');

// Create a gauge to track the total number of dietaries.
const dietariesCountGauge = new client.Gauge({
  name: 'dietaries_total',
  help: 'Total number of dietaries',
});

// Create a gauge to track the total number of items.
const itemsCountGauge = new client.Gauge({
  name: 'items_total',
  help: 'Total number of items',
});

// Function to query and update dietary count
async function updateDietaryCount() {
  try {
    const count = await Dietary.countDocuments();
    dietariesCountGauge.set(count);
  } catch (error) {
    console.error('Error updating dietaries count:', error);
  }
}

// Function to query and update item count
async function updateItemCount() {
  try {
    const count = await Item.countDocuments();
    itemsCountGauge.set(count);
  } catch (error) {
    console.error('Error updating items count:', error);
  }
}

// Start periodic updates (e.g., every minute)
const UPDATE_INTERVAL_MS = 60000; // one minute
setInterval(updateDietaryCount, UPDATE_INTERVAL_MS);
setInterval(updateItemCount, UPDATE_INTERVAL_MS);

updateDietaryCount();
updateItemCount();

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