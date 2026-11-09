// RS256 verification: this service gets only the public key. It can check
// that a token was signed by auth, but it cannot create tokens itself.
const crypto = require("crypto");

function requiredKey(name) {
  const value = process.env[name];
  if (!value) {
    // Fail at startup, not on the first request
    console.error(`${name} is not set. Refusing to start without a verification key.`);
    process.exit(1);
  }
  // Accept a PEM written on one line with literal \n
  return value.replace(/\\n/g, "\n");
}

const publicKey = requiredKey("JWT_PUBLIC_KEY");
try {
  crypto.createPublicKey(publicKey);
} catch (err) {
  console.error(`JWT_PUBLIC_KEY is not a valid PEM public key: ${err.message}`);
  process.exit(1);
}

const issuer = process.env.JWT_ISSUER || "restauranty-auth";
const audience = process.env.JWT_AUDIENCE || "restauranty-api";

module.exports = {
  publicKey,
  verifyOptions: { algorithms: ["RS256"], issuer, audience },
};
