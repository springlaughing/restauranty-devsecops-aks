#!/usr/bin/env bash
# Tests the rules at the edge (#10): the user list closed at the Gateway,
# the login limit and the flood limit. Prints PASS or FAIL for each check.
#
# Run it twice for the before/after evidence:
#   ./scripts/test-edge.sh                                     # before: no edge rules
#   kubectl apply -f k8s/app/edge-rules.yaml -f k8s/platform/rate-limit.yaml
#   ./scripts/test-edge.sh                                     # after: every check passes
#
# Runs from your own machine, like a stranger on the internet. The limit
# tests use your IP address: afterwards, login answers 429 for about a
# minute, until the count drains.
set -uo pipefail

URL="https://restauranty.aks.springlaughing.dev"

pass=0; fail=0
result() {  # result <check> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  PASS  %-48s %s\n' "$1" "$3"; pass=$((pass + 1))
  else
    printf '  FAIL  %-48s expected %s, got %s\n' "$1" "$2" "$3"; fail=$((fail + 1))
  fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 --path-as-is "$@"; }
wrong_login() {
  code -X POST "$URL/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"email":"nobody@example.com","password":"wrong"}'
}

echo "Edge rules: $(kubectl get accesspolicy,ratelimitpolicy -A -o name 2>/dev/null | wc -l) policies"

echo; echo "The app still works"
result "GET /  (the website)" 200 "$(code "$URL/")"
result "GET /api/auth  (auth is up)" 200 "$(code "$URL/api/auth")"
result "GET /api/items/items, no token  (reaches the app)" 401 "$(code "$URL/api/items/items")"
result "POST /api/auth/login, wrong password" 401 "$(wrong_login)"

echo; echo "The user list is closed at the Gateway (403 = Gateway, 401 = the app)"
for p in /api/auth/users /api/auth/USERS /api/auth/Users /api/auth/users/ \
         /api/auth/users/000000000000000000000000; do
  result "GET $p" 403 "$(code "$URL$p")"
done

echo; echo "Password guessing: 20 wrong logins in a row"
codes=$(for i in $(seq 20); do wrong_login; echo; done)
n401=$(grep -c '^401$' <<<"$codes"); n429=$(grep -c '^429$' <<<"$codes")
echo "        answers: $n401 x 401, $n429 x 429"
result "some guesses refused with 429" yes "$([ "$n429" -gt 0 ] && echo yes || echo no)"

echo; echo "Flood: 300 requests at once from one address"
# One curl, 50 requests in flight over shared connections: well above
# 50/s. (300 separate curl processes are too slow: each does its own TLS
# handshake, and they reached only about 46 requests/s, under the limit.)
codes=$(curl -s -Z --parallel-max 50 --max-time 15 -w '%{stderr}%{http_code}\n' "$URL/?n=[1-300]" 2>&1 >/dev/null)
n200=$(grep -c '^200$' <<<"$codes"); n429=$(grep -c '^429$' <<<"$codes")
echo "        answers: $n200 x 200, $n429 x 429"
result "some requests refused with 429" yes "$([ "$n429" -gt 0 ] && echo yes || echo no)"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
