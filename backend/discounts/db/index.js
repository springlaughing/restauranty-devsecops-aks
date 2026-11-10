// ℹ️ package responsible to make the connection with mongodb
// https://www.npmjs.com/package/mongoose
const mongoose = require("mongoose");
const client = require("prom-client");

// Create a gauge metric to track MongoDB connection status:
// 1 means connected, 0 means disconnected.
const mongoConnectionGauge = new client.Gauge({
  name: 'mongo_connection_status',
  help: 'Indicates MongoDB connection status: 1 for connected, 0 for disconnected'
});

// ℹ️ Sets the MongoDB URI for our app to have access to it.
// If no env has been set, we dynamically set it to whatever the folder name was upon the creation of the app

const MONGO_URI = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/Restauranty";

mongoose
  .connect(MONGO_URI)
  .then((x) => {
    const dbName = x.connections[0].name;
    console.log(`Connected to Mongo! Database name: "${dbName}"`);
    mongoConnectionGauge.set(1);  // Set gauge to 1 for connected
  })
  .catch((err) => {
    // The first connection failed, for example because MongoDB is still
    // starting after a cluster restart. Mongoose does not try a first
    // connection again, so this server would stay up without a database:
    // every login answers 500 while the health check still passes (#28).
    // So exit instead. Kubernetes restarts the container, and the new one
    // connects once MongoDB is ready. Kubernetes waits longer before each
    // restart (10 s, 20 s, 40 s, ... up to 5 minutes).
    // (A connection lost later is different: Mongoose reconnects by itself,
    // see the events below.)
    console.error(`Error connecting to mongo: ${err.message}. Exiting, so the container restarts.`);
    process.exit(1);
  });

// Also listen to connection events to update the metric dynamically.
mongoose.connection.on('disconnected', () => {
  console.log("MongoDB disconnected");
  mongoConnectionGauge.set(0);
});

mongoose.connection.on('reconnected', () => {
  console.log("MongoDB reconnected");
  mongoConnectionGauge.set(1);
});