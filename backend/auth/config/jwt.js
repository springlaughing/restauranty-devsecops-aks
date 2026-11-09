// RS256 signing: auth is the only service that holds the private key and can
// create tokens. Every service, auth included, checks tokens with the public
// key, which can verify a signature but never produce one.
const crypto = require("crypto");

function requiredKey(name) {
  const value = process.env[name];
  if (!value) {
    // Fail at startup, not on the first login
    console.error(`${name} is not set. Refusing to start without a signing key.`);
    process.exit(1);
  }
  // Accept a PEM written on one line with literal \n
  return value.replace(/\\n/g, "\n");
}

const privateKey = requiredKey("JWT_PRIVATE_KEY");

let publicKey;
try {
  publicKey = crypto
    .createPublicKey(privateKey)
    .export({ type: "spki", format: "pem" });
} catch (err) {
  console.error(`JWT_PRIVATE_KEY is not a valid PEM private key: ${err.message}`);
  process.exit(1);
}

const issuer = process.env.JWT_ISSUER || "restauranty-auth";
const audience = process.env.JWT_AUDIENCE || "restauranty-api";

module.exports = {
  privateKey,
  publicKey,
  signOptions: { algorithm: "RS256", expiresIn: "6h", issuer, audience },
  verifyOptions: { algorithms: ["RS256"], issuer, audience },
};
