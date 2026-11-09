# Security assessment: Restauranty

**What this is.** I took over Restauranty, an existing app. Before changing anything, I tested it for security problems, the way a security engineer does on day 1 at a new company. This document records each step: what I did, why, and what I found.

**How to read it.** Every step starts with its result in one line. The details come after. You can read any step on its own.

**Status:** steps 1 to 3 of 9 done (9 November 2026).

---

## Contents

- [Scope: what I tested and how](#scope-what-i-tested-and-how)
- [Method: how the testing is organised](#method-how-the-testing-is-organised)
- [Steps](#steps)
- [Step 1: Recon. What can be reached?](#step-1-recon-what-can-be-reached)
- [Steps 2 to 9](#step-2-normal-use)
- [Findings](#findings)

---

## Scope: what I tested and how

**In one line:** the original code, running only on my laptop, with fake users.

| Question | Answer |
| --- | --- |
| Which code? | The app as I received it: git tag `original`. The commits after it on `main` add docs and git settings, no app code. |
| Where does it run? | Only on my laptop. I never test someone else's system. |
| Which data? | Fake users only, with `@example.com` emails. |
| Who am I in the tests? | Sometimes nobody (no login), sometimes a normal logged-in user. Like a real attacker. |

**How the app runs locally**

| Part | Runs as | Address |
| --- | --- | --- |
| HAProxy (the front door) | Docker container | http://localhost (port 80) |
| Frontend (React) | `npm start` | port 3000, reached through HAProxy at `/` |
| auth service | `node server.js` | port 3001, reached through HAProxy at `/api/auth` |
| discounts service | `node server.js` | port 3002, reached through HAProxy at `/api/discounts` |
| items service | `node server.js` | port 3003, reached through HAProxy at `/api/items` |
| MongoDB | Docker container `mongo:8` | port 27017 |

All tests go through HAProxy, like real users would, unless a step says otherwise.

**Why this report is public.** Restauranty is a demo app for a bootcamp project, all data is fake, and showing the findings is the point of the project. At a real company, findings like these would not be published before they are fixed:

| Situation | What happens with the findings |
| --- | --- |
| I work for the company (the scenario here) | The report is confidential: it stays internal (a private repo or ticket system) until the fixes are live. |
| I am an outsider who found a problem | Coordinated disclosure: report it privately to the company, the way their `SECURITY.md` describes; give them time to fix it (often 90 days); publish only after that. |

How to report a problem in this project will be described in `SECURITY.md` (planned, issue #19).

---

## Method: how the testing is organised

**In one line:** I follow the OWASP Web Security Testing Guide, test every route the same way, and tag each finding with the OWASP Top 10.

**Normal testing vs security testing.** Normal testing asks: *does the app do what it should?* Security testing asks the opposite: *can I make it do what it should not?* For example: skip the login, use someone else's ID, send extra fields, send garbage, repeat a request 1000 times.

**White-box.** I have the source code. So I read the code first to know where to look, then prove each suspicion with a real request. A suspicion becomes a finding only when a request proves it.

**Three OWASP references, each with one job:**

| Reference | Its job here |
| --- | --- |
| **OWASP WSTG** (Web Security Testing Guide) | The checklist: *what* to test. It groups tests into categories (table below). |
| **OWASP Top 10 2025** | The labels: *which kind* of risk a finding is, e.g. "A01 Broken Access Control". |
| **OWASP ASVS** | The target: *what good looks like* when I fix something. |

**WSTG categories used in this assessment:**

| Code | Category | The question it asks |
| --- | --- | --- |
| INFO | Information gathering | What can be reached at all? |
| CONF | Configuration | Is anything set up in an unsafe way? |
| IDNT | Identity management | How are accounts and roles created? |
| ATHN | Authentication | Can I log in as someone I am not? |
| ATHZ | Authorization | Can I do things I am not allowed to do? |
| SESS | Session management | Is the login token safe? |
| INPV | Input validation | What happens with unexpected input? |
| ERRH | Error handling | Do errors leak secrets, or hide attacks? |
| CRYP | Cryptography | Are keys and hashing used correctly? |
| BUSL | Business logic | Can I abuse how the business works? |
| CLNT | Client side | What can go wrong in the browser? |

**Severity**

| Severity | Meaning |
| --- | --- |
| High | Anyone on the internet can read private data, change data, or act as another user. |
| Medium | Makes an attack easier, or needs some extra condition to cause harm. |
| Low | Good practice is missing; no direct harm alone. |

---

## Steps

| Step | What I do | WSTG categories | Status |
| --- | --- | --- | --- |
| 1 | **Recon.** List everything that can be reached. | INFO, CONF | Done |
| 2 | **Normal use.** Use the app like a real user and look at what it sends back. | - | Done |
| 3 | **Login and token.** Login messages, password guessing, the token itself. | IDNT, ATHN, SESS, CRYP | Done |
| 4 | **Permissions.** Every route without a token, with a bad token, with a fake token. | ATHZ | To do |
| 5 | **Data exposure.** What do answers contain that they should not? | ATHZ, ERRH | To do |
| 6 | **Input and business logic.** Extra fields, wrong IDs, a 100% coupon. | INPV, BUSL | To do |
| 7 | **Errors, logs, overload.** Error codes, what lands in the logs, heavy load. | ERRH | To do |
| 8 | **Tools.** `npm audit` and Semgrep, to catch what I missed. | - | To do |
| 9 | **Report.** Final findings table and fixes. | - | To do |

---

## Step 1: Recon. What can be reached?

**Result:** the app has 37 endpoints. 29 of them read or change data. **Only 1 of those 29 checks the login token.**

**Why this step.** You cannot test what you do not know exists. A full list of routes makes the testing complete: in later steps, every route gets the same tests.

**What I did**

1. Read `app.js` in each service: it shows which route files are used and under which path.
2. Read every file in `routes/`: it shows each method and path, and whether `isAuthenticated` (the token check) is used.
3. Called the app with `curl -D -` to see the response headers.
4. Checked which ports are open.

```bash
# Routes per file, and whether the file is used in app.js
grep -nE 'router\.(get|post|put|delete)\(' backend/*/routes/*.js
grep -n 'app.use' backend/*/app.js

# Response headers
curl -s -D - -o /dev/null http://localhost/api/items
```

### Route list

"Token checked" means the route uses the `isAuthenticated` middleware, which checks the login token.

**auth service** (`/api/auth`)

| Method | Path | What it does | Token checked |
| --- | --- | --- | --- |
| GET | `/api/auth` | Health check: "Auth Server UP!" | No (fine) |
| POST | `/api/auth/signup` | Creates an account | No (fine: must be public) |
| POST | `/api/auth/login` | Checks the password, returns a token | No (fine: must be public) |
| GET | `/api/auth/verify` | Checks the token, returns the user's data | **Yes** (the only one) |
| GET | `/api/auth/users` | Lists **all users** | **No** |
| GET | `/api/auth/users/:id` | Returns one user | **No** |
| PUT | `/api/auth/users` | Changes a user (the code has a bug: it crashes) | **No** |
| DELETE | `/api/auth/users/:id` | Deletes a user | **No** |

**discounts service** (`/api/discounts`)

| Method | Path | What it does | Token checked |
| --- | --- | --- | --- |
| GET | `/api/discounts` | Health check | No (fine) |
| GET | `/api/discounts/coupons`, `/coupons/:id` | Reads coupons | **No** |
| POST, PUT, DELETE | `/api/discounts/coupons`, `/coupons/:id` | Creates, changes, deletes coupons | **No** |
| GET | `/api/discounts/campaign`, `/campaign/:id` | Reads campaigns | **No** |
| POST, PUT, DELETE | `/api/discounts/campaign`, `/campaign/:id` | Creates, changes, deletes campaigns | **No** |

**items service** (`/api/items`)

| Method | Path | What it does | Token checked |
| --- | --- | --- | --- |
| GET | `/api/items` | Health check | No (fine) |
| GET | `/api/items/items`, `/items/:id` | Reads menu items | **No** |
| POST, PUT, DELETE | `/api/items/items`, `/items/:id` | Creates, changes, deletes menu items (POST and PUT upload an image to Cloudinary) | **No** |
| GET | `/api/items/dietary`, `/dietary/:id` | Reads dietary categories | **No** |
| POST, PUT, DELETE | `/api/items/dietary`, `/dietary/:id` | Creates, changes, deletes dietary categories | **No** |
| GET | `/api/items/orders`, `/orders/:id` | Reads all orders | **No** |
| PUT, DELETE | `/api/items/orders`, `/orders/:id` | Changes (crashes, same bug as users) and deletes orders | **No** |

**Every service**

| Method | Path | What it does | Token checked |
| --- | --- | --- | --- |
| GET | `/metrics` | Numbers for Prometheus (request counts, number of users and items) | No. Not reachable through HAProxy: there, `/metrics` goes to the frontend. |

### Other things I noticed

| What | Where | Why it matters |
| --- | --- | --- |
| CORS allows every website (`access-control-allow-origin: *`) | All API answers | Any website may call the API from a visitor's browser. |
| `x-powered-by: Express` header | All answers | Tells an attacker which framework to target. Small, but free to remove. |
| No security headers (no HSTS, CSP, X-Content-Type-Options, X-Frame-Options) | All answers | The browser gets no extra protection. HTTPS comes later on AKS. |
| Unused route files in discounts: `routes/auth.routes.js` and `routes/users.routes.js` | `backend/discounts/routes/` | Not reachable today. But one line in `app.js` would publish a second, unprotected user list. |
| Every service has copies of every database model, including `User` | `backend/*/models/` | Each service can read and change every collection, including users and password hashes. |
| MongoDB has no password | Local setup and `.env.example` (the connection string has no user) | Anyone who can reach port 27017 reads everything. To check how it will run on AKS. |

### Suspicions to prove in the next steps

Recon only gives suspicions. A suspicion becomes a finding when a real request proves it.

| # | Suspicion | Prove in step |
| --- | --- | --- |
| S1 | Anyone can list all users, maybe with password hashes, without logging in. | 4, 5 |
| S2 | Anyone can delete a user without logging in. | 4 |
| S3 | Anyone can create, change, and delete coupons, campaigns, items, dietary categories, and orders without logging in. | 4 |
| S4 | Every new account gets the `admin` role (`default: 'admin'` in the User model). | 3 |
| S5 | The token is signed with the `SECRET` from `.env.example`, which is public on GitHub. Anyone could make their own token. | 3 |
| S6 | The token contains personal data (address, phone). | 2, 3 |
| S7 | The login answer tells whether an email is registered. | 3 |
| S8 | No limit on login attempts: unlimited password guessing. | 3 |
| S9 | A bad or missing token gets "500 server error" instead of "401 not logged in". | 7 |
| S10 | Error answers show database details. | 7 |
| S11 | Personal data is written to the logs. | 7 |
| S12 | Extra fields in a request are saved as they are (mass assignment). | 6 |
| S13 | Anyone can create a 100% discount coupon. | 6 |
| S14 | Many fast logins could slow down the whole auth service (bcrypt runs in sync mode). | 7 |

---

## Step 2: Normal use

**Result:** just by using the app normally, three suspicions became findings. Every new account is `admin`. The login token contains my address and phone. The server writes that personal data into its log.

**Why this step.** Before attacking, see how the app works when used as intended. What the browser sends and gets back shows where to attack next.

**What I did**

1. Signed up in the browser at http://localhost as a fake user: Gordon Ramsoftware, `gordon@example.com`, "42 Overcooked Lane, Soggy Bottom".
2. Logged in with the browser's developer tools open (F12 → Network tab, "Preserve log" on, filter "Fetch/XHR").
3. Watched the auth service's terminal at the same time.

### What the browser sends at login

The browser sends the email and password as plain JSON. This is normal for a login form, but only HTTPS protects it on the way. Locally there is no HTTPS; on AKS there must be.

![Login request: email and password in plain text](evidence/02-login-request-password.png)

**Why the password is not hashed in the browser.** This is correct, not a bug. The server stores only a bcrypt hash of the password. To check a login, it must hash the real password and compare. If the browser sent a hash instead, that hash would simply become the new password: anyone who catches it could send it and log in. So the password travels as it is, and two different things protect it:

| Where | What protects the password | In Restauranty |
| --- | --- | --- |
| On the way, browser to server | HTTPS encrypts the whole connection | Missing locally (plain HTTP). Must be added on AKS. |
| Stored in the database | A slow hash (bcrypt) | Done right: bcrypt with cost 10 (`$2b$10$...`) |

The screenshot shows exactly what anyone between the user and the server (for example on public Wi-Fi) could read without HTTPS.

### What comes back

The answer allows any website to call the API (`Access-Control-Allow-Origin: *`).

![Login answer headers: CORS allows every origin](evidence/02-login-response-headers-cors.png)

After login, the frontend sends the token with every call to auth, in the `Authorization` header. Whoever has this string can act as Gordon for 6 hours.

![Verify request: the token in the Authorization header](evidence/02-verify-request-token.png)

### What the server writes in its log

The auth service's terminal during login. `req.payload` is the content of the token. The `/verify` route prints it with `console.log`:

```text
POST /api/auth/login 200 173.678 ms - 400
req.payload {
  _id: '6af1c528e76ced969e1a2240',
  email: 'gordon@example.com',
  name: 'Gordon',
  surname: 'Ramsoftware',
  address: '42 Overcooked Lane, Soggy Bottom',
  phoneNumber: '\t555-NO-SALT',
  role: 'admin',
  iat: 1794230599,
  exp: 1794252199
}
GET /api/auth/verify 200 9.606 ms - 227
```

This one log shows three things:

| What the log shows | Suspicion | Now |
| --- | --- | --- |
| `role: 'admin'`: I signed up as a normal person and got admin rights. | S4 | Finding F1 |
| `address` and `phoneNumber` are inside the token. Anyone holding the token can read them. | S6 | Finding F2 |
| The server writes this personal data into its log on every page load. Once logs are collected (Loki on AKS), they stay there for the whole retention time. | S11 | Finding F3 |

Also noticed: the phone number was saved with an invisible tab character at the start (`\t555-NO-SALT`). The app stores input as it comes, without trimming or checking. To test in step 6.

## Step 3: Login and token

**Goal:** test how accounts are created and how login works, and look inside the token.

| Test | Question | WSTG | Result |
| --- | --- | --- | --- |
| 3a | Does the login answer reveal which emails exist? | IDNT | **Yes**, three ways (F4) |
| 3b | How weak can a password be? | ATHN | **Very weak** (F5) |
| 3c | Can I guess passwords without limit? | ATHN | **Yes**, about 10 per second (F6) |
| 3d | Does logout really log you out? | SESS | **No**, the token keeps working (F7) |
| 3e | Can I change the token myself? | SESS | **No**, refused. But with 500 instead of 401 (F8) |
| 3f | Can I make my own token from nothing? | SESS, CRYP | **Yes**, with the secret from GitHub (F9) |

### Test 3a: does login reveal which emails exist?

**Result:** yes. The message, the size and the time of the answer all show whether an email has an account. (Finding F4.)

**Why it matters.** An attacker with a list of emails first finds out which ones have an account here. Then they spend all their password guesses on real accounts. This makes every other attack cheaper.

**What I did:** tried to log in with an email that does not exist, then with Gordon's email and a wrong password, then signed up again with Gordon's email.

```bash
curl -s -X POST http://localhost/api/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"nobody@example.com","password":"Whatever1"}'
curl -s -X POST http://localhost/api/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"gordon@example.com","password":"Whatever1"}'
curl -s -X POST http://localhost/api/auth/signup -H 'Content-Type: application/json' \
  -d '{"name":"X","surname":"Y","email":"gordon@example.com","password":"Whatever1","address":"Z","phoneNumber":"1"}'
```

What came back:

```text
{"message":"User not found."}
{"message":"Email or Password Incorrect"}
{"message":"Email already in use."}
```

The auth service's log for the two logins:

```text
POST /api/auth/login 401 19.703 ms - 29    <- email does not exist
POST /api/auth/login 401 86.482 ms - 41    <- email exists, wrong password
```

| Clue | Email does not exist | Email exists | |
| --- | --- | --- | --- |
| Message | "User not found." | "Email or Password Incorrect" | Different |
| Size of the answer | 29 bytes | 41 bytes | Different |
| Time | about 20 ms | about 86 ms | Different |

**Why the time is different.** If the email does not exist, the code stops at once. If it exists, the code checks the password with bcrypt, which is slow on purpose. So even with the same message, the clock would still tell. A full fix also runs bcrypt when the email does not exist (against a dummy hash), so both cases take the same time.

**Secure answer:** the same message, the same size, and about the same time for both cases. For signup, many sites always answer "check your email", whether the account exists or not.

Also seen: after "Email already in use." the auth service logs a crash (`TypeError: Cannot destructure property 'email' of 'createdUser'`). The user gets the right answer, but the log fills with false errors. To look at in step 7.

### Test 3b: how weak can a password be?

**Result:** the app accepts `Password1`, `Qwerty123` and even its own name, `Restauranty1`. Only passwords without a capital letter or a number are refused. (Finding F5.)

**Why it matters.** Weak passwords make password guessing (test 3c) succeed fast. And because every new account is admin (F1), one guessed password gives full control.

**What I did:** tried to sign up with five weak passwords.

```bash
for pw in aaaaaa Abcde1 Password1 Qwerty123 Restauranty1; do
  curl -s -X POST http://localhost/api/auth/signup -H 'Content-Type: application/json' \
    -d "{\"name\":\"Weak\",\"surname\":\"Pw\",\"email\":\"weak-$pw@example.com\",\"password\":\"$pw\",\"address\":\"1 Easy Street\",\"phoneNumber\":\"1\"}"
done
```

| Password | Why I tried it | Result |
| --- | --- | --- |
| `aaaaaa` | Control: breaks the rule (no capital, no number) | Refused (400) |
| `Abcde1` | The shortest password the rule allows | **Accepted** (201) |
| `Password1` | One of the most common passwords in the world | **Accepted** (201) |
| `Qwerty123` | Keyboard pattern, in every top-100 list | **Accepted** (201) |
| `Restauranty1` | The site's own name: the first thing an attacker tries | **Accepted** (201) |

**Secure answer:** at least 8 characters (NIST SP 800-63B; 12 or more is better), and refuse passwords from lists of leaked passwords. Length and "not a known password" protect more than "one capital, one number".

### Test 3c: can I guess passwords without limit?

**Result:** yes. 50 wrong passwords in 4.9 seconds, none blocked, and the right password still worked afterwards. (Finding F6.)

**Why it matters.** At this speed, an attacker tries the 1,000 most common passwords on one account in under 2 minutes. Together with F4 (find which emails exist), F5 (weak passwords allowed) and F1 (every account is admin), this is a complete attack: find a real email, guess `Password1`, become admin.

**What I did:** sent 50 wrong passwords for Gordon, one after another, counted the answers, then sent the right password.

```bash
for i in $(seq 1 50); do
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost/api/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"gordon@example.com\",\"password\":\"WrongGuess$i\"}"
done | sort | uniq -c

curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost/api/auth/login \
  -H 'Content-Type: application/json' -d '{"email":"gordon@example.com","password":"RawChicken1"}'
```

```text
     50 401
50 wrong guesses took 4.9 seconds
Right password after 50 failures: HTTP 200
```

| Measured | Value |
| --- | --- |
| Blocked answers (429) | 0 of 50 |
| Speed | about 10 guesses per second, from one terminal |
| Per day | about 880,000 guesses |
| Account locked after 50 failures? | No |

This was one terminal sending one request at a time. Many requests in parallel would be faster, until the server's CPU is full (bcrypt is slow on purpose).

**Secure answer:** after a few failures, answer `429 Too Many Requests`. Two kinds of limit work together:

| Limit | Stops | Weak spot |
| --- | --- | --- |
| Per IP address, at the Gateway | One machine guessing fast | Attackers with many IP addresses (a botnet) |
| Per account, in the app | Guessing on one account from many IPs | If it locks the account for good, an attacker can lock out real users on purpose. So slow down for a while, don't lock forever. |

### Test 3d: does logout really log you out?

**Result:** no. After logout, a copy of the token still works for the rest of its 6 hours. (Finding F7.)

**Why it matters.** A token can be stolen: from a shared computer, a browser extension, or a script injected into the page. The user clicks "Log out" and thinks they are safe, but whoever has a copy keeps full access until the token expires.

**What I did**

1. Logged in as Gordon in the browser.
2. Copied the token from the developer tools (Application → Local Storage → `authToken`).
3. Clicked "Log out" in the app.
4. Used the copied token from the terminal:

```bash
TOKEN='<the copied token>'
curl -s -w '\nHTTP %{http_code}\n' http://localhost/api/auth/verify -H "Authorization: Bearer $TOKEN"
```

```text
{"_id":"6af1c528e76ced969e1a2240","email":"gordon@example.com","name":"Gordon","surname":"Ramsoftware","address":"42 Overcooked Lane, Soggy Bottom","phoneNumber":"\t555-NO-SALT","role":"admin","iat":1794230599,"exp":1794252199}
HTTP 200
```

**Why it works.** Logout only deletes the token in the browser. The server is never told. From `client/src/context/auth.context.jsx`:

```js
const logOutUser = () => {
  removeToken();        // deletes the token from Local Storage
  authenticateUser();   // no token left: shows "logged out", no call to the server
};
```

The server checks only the signature and the expiry time (`exp`). A token stays valid until it expires, whatever the user does.

**Secure answer:** logout calls the server, and the server refuses that token from then on (a list of revoked tokens, or server-side sessions). Short token lifetimes help too: 15 minutes plus a refresh token, instead of 6 hours.

### Test 3e: can I change the token myself?

**Result:** no. The server sees the change and refuses the token: the signature check works. **But** it answers "500 server error" instead of "401 not allowed". (Finding F8.)

**Why it matters.** A 500 means "the server is broken". A 401 means "you are not allowed". When attacks come back as 500, they hide among real errors. Later, monitoring would raise "server is failing" alerts instead of "someone is attacking".

**What I did:** took Gordon's token, changed the expiry time (`exp`) to the year 2286, and kept the old signature.

```bash
HEADER=$(echo "$TOKEN" | cut -d. -f1)
SIG=$(echo "$TOKEN" | cut -d. -f3)
NEW=$(printf '{"_id":"6af1c528e76ced969e1a2240","email":"gordon@example.com","role":"admin","exp":9999999999}' \
  | base64 -w0 | tr '+/' '-_' | tr -d '=')
curl -s -w '\nHTTP %{http_code}\n' http://localhost/api/auth/verify -H "Authorization: Bearer $HEADER.$NEW.$SIG"
```

What came back:

```text
{"message":"Internal server error. Check the server console"}
HTTP 500
```

The auth service's log (shortened; the full log has about 20 more lines of stack trace):

```text
ERROR GET /api/auth/verify UnauthorizedError: invalid signature
    at new UnauthorizedError (.../express-jwt/dist/errors/UnauthorizedError.js:22:28)
    ...
  code: 'invalid_token',
  status: 401,
  inner: JsonWebTokenError: invalid signature
GET /api/auth/verify 500 9.294 ms - 61
```

**Why 500.** The error itself says `status: 401`: the token library knew this was "not allowed". But the app's error handler (`backend/*/error-handling/index.js`) turns every error into 500. All three services share this handler.

**Good:** the client gets only a short message, not the stack trace.

**Secure answer:** `401` with a short message, and one short log line such as `401 invalid signature`, so alerts can count attacks.

### Test 3f: can I make my own token from nothing?

**Result:** yes. The server signs and checks tokens with the secret `MySecret1!`, and that same secret is published in the GitHub repo. With it I made an admin token for a user that does not exist, and the server accepted it. (Finding F9.)

**How the server checks a token (HS256).** The app uses HS256: **one secret, no key pair**. The same secret does two jobs:

| Job | Who | When |
| --- | --- | --- |
| Sign a token | auth | At login |
| Check a token | every service | On every request |

The check only asks: "was this token signed with my secret?" So **anyone who knows the server's secret can sign tokens the server accepts**. There is no public or private key in this app (yet).

**Why the published secret works here.** The server runs with `MySecret1!` because its `.env` file was made by copying `.env.example`, the normal setup step. So the server's real secret *is* the published one. If the server used a different, random secret, this attack would fail with `invalid signature`, like in test 3e.

**Why it matters.** Whoever has the secret can be any user, with any role, for as long as they like. No password needed, no login, no trace in the login logs.

**What I did**

1. Read the secret from the public repo, like any stranger could:

```bash
curl -s https://raw.githubusercontent.com/springlaughing/restauranty-devsecops-aks/main/backend/auth/.env.example
```

```text
SECRET=MySecret1!
MONGODB_URI="mongodb://127.0.0.1:27017/resturanty"
...
```

2. Signed my own token for a made-up user, "Sneaky", with role `admin`:

```bash
cd backend/auth   # this folder has the jsonwebtoken library installed
FORGED=$(node -e '
  const jwt = require("jsonwebtoken");
  console.log(jwt.sign(
    { _id: "000000000000000000000000", email: "sneaky@example.com", name: "Sneaky", role: "admin" },
    "MySecret1!",
    { algorithm: "HS256", expiresIn: "1h" }
  ));
')
curl -s -w '\nHTTP %{http_code}\n' http://localhost/api/auth/verify -H "Authorization: Bearer $FORGED"
```

3. The server accepted it:

```text
{"_id":"000000000000000000000000","email":"sneaky@example.com","name":"Sneaky","role":"admin","iat":1794232667,"exp":1794236267}
HTTP 200
```

4. The auth service's log looks completely normal:

```text
req.payload {
  _id: '000000000000000000000000',
  email: 'sneaky@example.com',
  name: 'Sneaky',
  role: 'admin',
  iat: 1794232667,
  exp: 1794236267
}
GET /api/auth/verify 200 9.368 ms - 128
```

**Hard to detect.** No error, no warning: a forged token looks exactly like a real one. Only two quiet clues show the attack:

| Clue | Real user | Forged token |
| --- | --- | --- |
| A login comes first in the log | Yes: `POST /api/auth/login 200` | No login at all |
| The user exists in the database | Yes | No: `000000000000000000000000` does not exist. The server never checks; it trusts the token. |

Spotting this needs a rule that compares the two ("token used, but no login for this user") or a database check. Simple log alerts will not see it. This is why preventing forgery (fixes below) matters more than detecting it.

**How the secret got into GitHub.** The git history shows it:

| When | Commit | What happened |
| --- | --- | --- |
| April 2025 | `a618bdf` "addinv envs" | The real config files `backend/.env` and `client/src/.env` were committed, with `SECRET=MySecret1!` |
| June 2025 | `f24aff8` "changes done" | The `.env` files were deleted from git, and `.env.example` files were created in each service with the same values |

So the "example" is most likely the old real development config, copied instead of replaced with placeholders. Probably not on purpose: a common slip.

**Deleted is not gone.** The old `.env` is still in the history: `git show a618bdf:backend/.env` prints it. I checked it with the values hidden:

| Value in the old `.env` | Real secret? |
| --- | --- |
| `SECRET` | Yes: `MySecret1!`, the one used in this test |
| `MONGODB_URI` | **Contains a username and password**, for a MongoDB on `localhost`. Low risk (someone's own laptop), but a real credential in public history. Not repeated here. |
| `CLOUD_NAME`, `CLOUD_API_KEY`, `CLOUD_API_SECRET` | No: all three are the same placeholder word |

(Finding F10.) Fix: change any secret that was ever pushed (rewriting history does not help once others have copies), and scan every commit for secrets in the pipeline, for example with gitleaks.

**Being precise about it.** This attack works only where the server uses the published secret. My local run does, because I followed the normal setup (`cp .env.example .env`), and the README shows the same value. I do not know if any real deployment used it. The finding is that **the app starts with a publicly known secret and never complains**. This is the classic "default credentials" problem.

**Even a changed secret is weak if a person chose it.** `MySecret1!` is a password, not a random key. With HS256, anyone who has one valid token can guess the secret offline, on their own computer, with no rate limit, at billions of guesses per second on a graphics card. Getting a valid token is easy here: sign up (F1).

**Bigger design problem: one secret does two jobs.** With HS256, the same secret creates tokens and checks them. So every service that checks tokens could also create them. If one service is hacked, the attacker can sign admin tokens for all of them.

**Secure answer**

| Fix | What it solves |
| --- | --- |
| No default value: the app refuses to start without a real secret | Nobody runs with the example by accident |
| A long random key, not a password (for example `openssl rand -base64 48`) | Offline guessing becomes impossible |
| Keys stored outside the code (Azure Key Vault) | The secret never sits in Git |
| RS256: a key pair. Only auth has the private key to sign; the other services get only the public key to check | A hacked service can check tokens, but can no longer create them |

## Step 4: Permissions

**Goal:** call every route from the route list without a token, with a broken token, and with a fake token.

*To do.*

## Step 5: Data exposure

**Goal:** check every answer for data that should not be there: password hashes, other people's personal data, internal details.

*To do.*

## Step 6: Input and business logic

**Goal:** send what the app does not expect (extra fields, wrong IDs, missing fields) and abuse business rules (a 100% coupon).

*To do.*

## Step 7: Errors, logs, overload

**Goal:** check error codes, what ends up in the logs, and what heavy load does.

*To do.*

## Step 8: Tools

**Goal:** run `npm audit` (known vulnerable packages) and Semgrep (risky code patterns) to catch what manual testing missed.

*To do.*

## Step 9: Report

**Goal:** the final findings table, with severity, OWASP tag, proof, and the fix.

*To do.*

---

## Findings

A finding is a suspicion that a real request has proved. Each one links to the step with the proof.

| ID | Finding | Severity | OWASP 2025 | Proof |
| --- | --- | --- | --- | --- |
| F1 | Every new account gets the `admin` role. Anyone who signs up can manage the whole restaurant. | High | A01 Broken Access Control | [Step 2](#step-2-normal-use) |
| F2 | The login token contains personal data (email, address, phone). A token is only encoded, not encrypted: anyone holding it can read it. | Medium | A04 Cryptographic Failures, GDPR | [Step 2](#step-2-normal-use) |
| F3 | The server writes personal data (address, phone) into its log on every page load. | Medium | A09 Security Logging and Alerting Failures, GDPR | [Step 2](#step-2-normal-use) |
| F4 | Login reveals which emails have an account: by the message, the size, and the time of the answer. Signup reveals it too. | Medium | A07 Authentication Failures | [Test 3a](#test-3a-does-login-reveal-which-emails-exist) |
| F5 | Weak passwords are accepted: `Password1`, `Qwerty123`, `Restauranty1`. | Medium | A07 Authentication Failures | [Test 3b](#test-3b-how-weak-can-a-password-be) |
| F6 | No limit on login attempts: about 10 guesses per second, no blocking, no slowdown. | High | A07 Authentication Failures | [Test 3c](#test-3c-can-i-guess-passwords-without-limit) |
| F7 | Logout does not end the session: a copied token works for its full 6 hours after logout. | Medium | A07 Authentication Failures | [Test 3d](#test-3d-does-logout-really-log-you-out) |
| F8 | A refused token is answered with "500 server error" instead of "401 not allowed". Attacks look like outages. | Medium | A10 Mishandling of Exceptional Conditions | [Test 3e](#test-3e-can-i-change-the-token-myself) |
| F9 | The server signs and checks tokens with one secret (HS256), and runs with `MySecret1!`, the value published in `.env.example` and the README. With it, anyone can make an admin token for any user, even one that does not exist. The app never complains about the default. | High | A02 Security Misconfiguration, A04 Cryptographic Failures | [Test 3f](#test-3f-can-i-make-my-own-token-from-nothing) |
| F10 | Real config files (`.env`) were committed in April 2025 and are still in the git history, including a MongoDB username and password (for `localhost`). | Low | A02 Security Misconfiguration | [Test 3f](#test-3f-can-i-make-my-own-token-from-nothing) |
