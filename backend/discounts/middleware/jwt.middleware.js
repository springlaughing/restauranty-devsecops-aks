const { expressjwt: jwt } = require("express-jwt");
const { publicKey, verifyOptions } = require("../config/jwt");

// Instantiate the JWT token validation middleware.
// Only RS256 tokens signed by auth's private key, with the expected issuer
// and audience, are accepted. Anything else is an UnauthorizedError (401).
const isAuthenticated = jwt({
  secret: publicKey,
  ...verifyOptions,
  requestProperty: "payload",
  getToken: getTokenFromHeaders,
});

// Function used to extract the JWT token from the request's 'Authorization' Headers
function getTokenFromHeaders(req) {
  // Check if the token is available on the request Headers
  if (
    req.headers.authorization &&
    req.headers.authorization.split(" ")[0] === "Bearer"
  ) {
    // Get the encoded token string and return it
    const token = req.headers.authorization.split(" ")[1];
    return token;
  }

  return null;
}

// Export the middleware so that we can use it to create protected routes
module.exports = {
  isAuthenticated,
};
