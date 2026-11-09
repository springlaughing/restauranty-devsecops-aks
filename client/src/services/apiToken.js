import axios from "axios";

// The admin pages call items and discounts with plain axios. Those services
// require a login token, so this adds the token to every request that goes
// to our own API. Requests to any other website never get the token.

// Where our API lives: the same addresses the pages use.
const apiOrigins = new Set(
  [
    process.env.REACT_APP_SERVER_URL,
    process.env.REACT_APP_SERVER_AUTH_URL,
    process.env.REACT_APP_SERVER_DISCOUNTS_URL,
    process.env.REACT_APP_SERVER_ITEMS_URL,
    "http://localhost:80",
    window.location.origin,
  ]
    .filter(Boolean)
    .map((url) => new URL(url, window.location.origin).origin)
);

function isOurApi(url) {
  try {
    return apiOrigins.has(new URL(url, window.location.origin).origin);
  } catch {
    return false;
  }
}

axios.interceptors.request.use((config) => {
  const token = localStorage.getItem("authToken");
  if (token && isOurApi(config.url)) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});
