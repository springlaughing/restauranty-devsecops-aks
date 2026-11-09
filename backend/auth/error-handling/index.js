module.exports = (app) => {
  app.use((req, res, next) => {
    // this middleware runs whenever requested page is not available
    res.status(404).json({ message: "This route does not exist" });
  });

  app.use((err, req, res, next) => {
    // A missing, forged, expired or malformed token is the caller's fault,
    // not a server failure: answer 401 so attacks don't look like outages.
    // One log line per refusal, e.g. "AUTH 401 GET /api/auth/verify: invalid signature",
    // so logs and alerts can count them.
    if (err.name === "UnauthorizedError") {
      console.warn(`AUTH 401 ${req.method} ${req.originalUrl}: ${err.message}`);
      if (!res.headersSent) {
        res.status(401).json({ message: "Invalid or missing token" });
      }
      return;
    }

    // Bad input from the caller (an invalid id, a missing field): a short
    // answer. The details (model and field names) go only to the log,
    // because they tell an attacker how the database looks.
    if (err.name === "CastError" || err.name === "ValidationError") {
      console.warn(`BAD INPUT 400 ${req.method} ${req.originalUrl}: ${err.message}`);
      if (!res.headersSent) {
        res.status(400).json({
          message: err.name === "CastError" ? "Invalid id" : "Invalid or missing fields",
        });
      }
      return;
    }

    // Anything else is a real server error: log it in full, answer briefly
    console.error("ERROR", req.method, req.path, err);

    // only render if the error ocurred before sending the response
    if (!res.headersSent) {
      res.status(500).json({ message: "Internal server error" });
    }
  });
};
