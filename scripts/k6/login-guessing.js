// Password guessing against the real login (#15): the attack for the demo.
//
// One attacker (one IP address: the laptop) tries a new password twice per
// second for 4 minutes, for one email address. What should happen:
//   - the first ~15 tries reach auth and get 401 (wrong password)
//   - then the Gateway's login limit (10 per minute per IP, burst 5) answers
//     most tries with 429 before they reach auth; about 10 per minute still
//     get through and get 401
//   - after about 3 to 5 minutes the alert RestaurantyLoginGuessing
//     (more than 20 failed logins in 5 minutes) reaches Slack
//
// Run (from the repo root):
//   k6 run scripts/k6/login-guessing.js
// Other target or account:
//   k6 run -e BASE=https://... -e EMAIL=someone@example.com scripts/k6/login-guessing.js
//
// The email does not need to exist: since the code fix of entry 5, an unknown
// email and a wrong password get the same answer (401), so the attacker learns
// nothing either way. Only run this against systems you own.
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE || 'https://restauranty.aks.springlaughing.dev';
const EMAIL = __ENV.EMAIL || 'admin@restauranty.example';

// One counter per answer, shown in k6's summary at the end
const wrongPassword = new Counter('answers_401_wrong_password');
const rateLimited = new Counter('answers_429_rate_limited');
const otherAnswer = new Counter('answers_other');

export const options = {
  scenarios: {
    guessing: {
      executor: 'constant-arrival-rate', // a fixed pace, however fast the answers come
      rate: 2,
      timeUnit: '1s',                    // 2 tries per second = 120 per minute
      duration: '4m',
      preAllocatedVUs: 5,
    },
  },
  // 401 and 429 are the expected answers here, not failures of the test
  thresholds: {},
};

export default function () {
  const guess = `Guess-${Math.floor(Math.random() * 1e9)}`;
  const res = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: guess }),
    { headers: { 'Content-Type': 'application/json' }, responseCallback: http.expectedStatuses(401, 429) },
  );
  if (res.status === 401) wrongPassword.add(1);
  else if (res.status === 429) rateLimited.add(1);
  else otherAnswer.add(1);
  check(res, { 'refused (401 or 429)': (r) => r.status === 401 || r.status === 429 });
}
