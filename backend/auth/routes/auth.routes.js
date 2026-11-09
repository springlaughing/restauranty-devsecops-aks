const express = require("express");
const router = express.Router();

// ℹ️ Handles password encryption
const bcrypt = require("bcryptjs");

// ℹ️ Handles password encryption
const jwt = require("jsonwebtoken");

// Require the User model in order to interact with the database
const User = require("../models/User.model.js");

// Require necessary (isAuthenticated) middleware in order to control access to specific routes
const { isAuthenticated } = require("../middleware/jwt.middleware.js");

// RS256 private key and signing options (algorithm, expiry, issuer, audience)
const { privateKey, signOptions } = require("../config/jwt");

// How many rounds should bcrypt run the salt (default - 10 rounds)
const saltRounds = 10;

// One answer for every failed login, so it never tells whether an email
// has an account.
const LOGIN_FAILED = "Email or Password Incorrect";

// A bcrypt hash that matches no real password. When the email is unknown,
// login still compares against it, so that answer takes as long as a wrong
// password: the response time does not reveal which emails exist either.
const DUMMY_HASH = bcrypt.hashSync("no-account-has-this-password", saltRounds);

// POST /auth/signup  - Creates a new user in the database
router.post("/signup", (req, res, next) => {
  const { name, surname, email, password, address, phoneNumber } = req.body;

  // Check if email or password or name are provided as empty strings
  if (email === "" || password === "" || name === "" || surname === "" || address === "" || phoneNumber === "") {
    res.status(400).json({ message: "Provide email, password, name, surname, address and phone number." });
    return;
  }

  // // This regular expression check that the email is of a valid format
  // const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  // if (!emailRegex.test(email)) {
  //   res.status(400).json({ message: "Provide a valid email address." });
  //   return;
  // }

  // This regular expression check that the phonenumber is of a valid format
  // const phoneRegex = /^9[1236]{1}[0-9]{7}$/;
  // if (!phoneRegex.test(email)) {
  //   res.status(400).json({ message: "Provide a valid phone number." });
  //   return;
  // }

  // This regular expression checks password for special characters and minimum length
  const passwordRegex = /(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{6,}/;
  if (!passwordRegex.test(password)) {
    res.status(400).json({
      message:
        "Password must have at least 6 characters and contain at least one number, one lowercase and one uppercase letter.",
    });
    return;
  }

  // Check the users collection if a user with the same email already exists
  User.findOne({ email })
    .then((foundUser) => {
      // If the user with the same email already exists, send an error response
      if (foundUser) {
        res.status(400).json({ message: "Email already in use." });
        return;
      }

      // If email is unique, proceed to hash the password
      const salt = bcrypt.genSaltSync(saltRounds);
      const hashedPassword = bcrypt.hashSync(password, salt);

      // Create the new user in the database
      // We return a pending promise, which allows us to chain another `then`
      return User.create({ email, password: hashedPassword, name, surname, address, phoneNumber });
    })
    .then((createdUser) => {
      // Deconstruct the newly created user object to omit the password
      // We should never expose passwords publicly
      const { email, name, surname, address, phoneNumber, _id } = createdUser;

      // Create a new object that doesn't expose the password
      const user = { email, name, surname, address, phoneNumber, _id };

      // Send a json response containing the user object
      res.status(201).json({ user: user });
    })
    .catch((err) => next(err)); // In this case, we send error handling to the error handling middleware.
});

// POST  /auth/login - Verifies email and password and returns a JWT
router.post("/login", (req, res, next) => {
  const { email, password } = req.body;

  // Check that email and password are given and not empty
  if (!email || !password) {
    res.status(400).json({ message: "Provide email and password." });
    return;
  }

  // Check the users collection if a user with the same email exists.
  // The password hash is hidden by default (select: false in the User model),
  // so ask for it here, the only place that needs it.
  User.findOne({ email })
    .select("+password")
    .then((foundUser) => {
      if (!foundUser) {
        // Same work and same answer as a wrong password
        bcrypt.compareSync(password, DUMMY_HASH);
        res.status(401).json({ message: LOGIN_FAILED });
        return;
      }

      // Compare the provided password with the one saved in the database
      const passwordCorrect = bcrypt.compareSync(password, foundUser.password);

      if (passwordCorrect) {
        // Deconstruct the user object to omit the password
        const { _id, email, name, surname, address, phoneNumber, role } = foundUser;

        // Create an object that will be set as the token payload
        const payload = { _id, email, name, surname, address, phoneNumber, role };

        // Create a JSON Web Token and sign it with auth's private key (RS256)
        const authToken = jwt.sign(payload, privateKey, signOptions);

        // Send the token as the response
        res.status(200).json({ authToken: authToken });
      } else {
        res.status(401).json({ message: LOGIN_FAILED });
      }
    })
    .catch((err) => next(err)); // In this case, we send error handling to the error handling middleware.
});

// GET  /auth/verify  -  Used to verify JWT stored on the client
router.get("/verify", isAuthenticated, (req, res, next) => {
  // If JWT token is valid the payload gets decoded by the
  // isAuthenticated middleware and is made available on `req.payload`
  console.log(`req.payload`, req.payload);

  // Send back the token payload object containing the user data
  res.status(200).json(req.payload);

});

module.exports = router;
