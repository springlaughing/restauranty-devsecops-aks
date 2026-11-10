#!/usr/bin/env bash
# Security tests against the running app (#13). Prints PASS or FAIL for each
# check and exits with 1 if any check fails, so the pipeline stops.
#
# The pipeline runs it after every deploy. You can run it by hand too:
#   ./scripts/test-api-security.sh                                   # the live app
#   ./scripts/test-api-security.sh https://restauranty.aks.springlaughing.dev
#
# It checks the findings from docs/security-assessment.md that a stranger on
# the internet could use:
#   - the user list is closed at the Gateway (F11, F14, F15)
#   - reading and changing data needs a token (F12, F13)
#   - forged tokens are refused (F9) and broken tokens give 401, not 500 (F8)
#   - no answer contains a `password` field (F11, F14, F15)
#
# For the last check it signs up one new test user with a random email and a
# random password, used once and never stored. One test user per run stays in
# the database (there is no public route to delete users, on purpose).
set -uo pipefail

URL="${1:-https://restauranty.aks.springlaughing.dev}"
J='Content-Type: application/json'

pass=0; fail=0
result() {  # result <check> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  PASS  %-55s %s\n' "$1" "$3"; pass=$((pass + 1))
  else
    printf '  FAIL  %-55s expected %s, got %s\n' "$1" "$2" "$3"; fail=$((fail + 1))
  fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 --path-as-is "$@"; }
# "no" if the text has no "password" key anywhere, "yes" if it has one
has_password() { grep -qi '"password"' <<<"$1" && echo yes || echo no; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
FAKE_ID=000000000000000000000000

echo "Testing $URL"

echo; echo "The app is up"
result "GET /  (the website)" 200 "$(code "$URL/")"
result "GET /api/auth  (auth answers)" 200 "$(code "$URL/api/auth")"

echo; echo "The user list is closed at the Gateway (403 = Gateway, 401 = the app)"
for p in /api/auth/users /api/auth/USERS /api/auth/users/$FAKE_ID; do
  result "GET $p" 403 "$(code "$URL$p")"
done
result "DELETE /api/auth/users/$FAKE_ID" 403 "$(code -X DELETE "$URL/api/auth/users/$FAKE_ID")"

echo; echo "Reading data without a token gets 401"
for p in /api/items/items /api/items/dietary /api/items/orders \
         /api/discounts/coupons /api/discounts/campaign; do
  result "GET $p" 401 "$(code "$URL$p")"
done

echo; echo "Changing data without a token gets 401"
result "POST /api/discounts/coupons  (a 100% coupon)" 401 "$(code -X POST "$URL/api/discounts/coupons" -H "$J" \
  -d '{"name":"FREE-LUNCH","discount":"100","start":"2026-01-01","end":"2099-12-31"}')"
result "POST /api/discounts/campaign" 401 "$(code -X POST "$URL/api/discounts/campaign" -H "$J" -d '{"name":"x"}')"
result "POST /api/items/items" 401 "$(code -X POST "$URL/api/items/items" -H "$J" -d '{"name":"x"}')"
result "PUT /api/items/items/$FAKE_ID" 401 "$(code -X PUT "$URL/api/items/items/$FAKE_ID" -H "$J" -d '{"price":0}')"
result "DELETE /api/items/items/$FAKE_ID" 401 "$(code -X DELETE "$URL/api/items/items/$FAKE_ID")"
result "DELETE /api/discounts/coupons/$FAKE_ID" 401 "$(code -X DELETE "$URL/api/discounts/coupons/$FAKE_ID")"

echo; echo "Forged and broken tokens get 401"
# An admin token signed HS256 with the secret that was public in the old .env
# (F9). Built with openssl here, so the test needs no Node.
exp=$(( $(date +%s) + 3600 ))
h=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
p=$(printf '{"_id":"%s","role":"admin","exp":%s}' "$FAKE_ID" "$exp" | b64url)
s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -hmac 'MySecret1!' -binary | b64url)
result "admin token signed with the old secret (HS256)" 401 "$(code "$URL/api/auth/verify" -H "Authorization: Bearer $h.$p.$s")"
# The same token with no signature at all ("alg": "none")
n=$(printf '{"alg":"none","typ":"JWT"}' | b64url)
result "admin token with no signature (alg none)" 401 "$(code "$URL/api/auth/verify" -H "Authorization: Bearer $n.$p.")"
result "garbage token" 401 "$(code "$URL/api/auth/verify" -H 'Authorization: Bearer not.a.token')"
result "no token" 401 "$(code "$URL/api/auth/verify")"

echo; echo "No answer contains a password field"
email="ci-test-$(openssl rand -hex 6)@example.com"
password="Ci$(openssl rand -hex 12)A1"   # random, never stored or printed
signup=$(curl -s --max-time 15 -X POST "$URL/api/auth/signup" -H "$J" -d "{\"email\":\"$email\",\"password\":\"$password\",
  \"name\":\"CI\",\"surname\":\"Test\",\"address\":\"none\",\"phoneNumber\":\"910000000\"}")
result "signup answer has a user" yes "$(grep -q '"user"' <<<"$signup" && echo yes || echo no)"
result "signup answer has a password field" no "$(has_password "$signup")"

login=$(curl -s --max-time 15 -X POST "$URL/api/auth/login" -H "$J" -d "{\"email\":\"$email\",\"password\":\"$password\"}")
token=$(sed -nE 's/.*"authToken":"([^"]+)".*/\1/p' <<<"$login")
result "login gives a token" yes "$([ -n "$token" ] && echo yes || echo no)"
result "login answer has a password field" no "$(has_password "$login")"

# The token's middle part is readable by anyone: it must not carry the hash
part=$(cut -d. -f2 <<<"$token" | tr '_-' '/+')
while [ $(( ${#part} % 4 )) -ne 0 ]; do part="$part="; done   # JWTs drop the = padding
payload=$(base64 -d <<<"$part" 2>/dev/null)
result "token payload has a password field" no "$(has_password "$payload")"

auth=(-H "Authorization: Bearer $token")
for p in /api/auth/verify /api/items/items /api/discounts/coupons /api/discounts/campaign; do
  body=$(curl -s --max-time 15 "${auth[@]}" "$URL$p")
  result "GET $p with the token has a password field" no "$(has_password "$body")"
done

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
