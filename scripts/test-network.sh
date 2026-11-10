#!/usr/bin/env bash
# Tests the network rules (#11): what must still work, and what an attacker
# must not reach. Prints PASS or FAIL for each check.
#
# Needs the attacker pods: kubectl apply -f k8s/proof/attacker-pods.yaml
#
# Run it twice for the before/after evidence:
#   kubectl delete -f k8s/network/policies.yaml && ./scripts/test-network.sh   # before: the attacks get through
#   kubectl apply  -f k8s/network/policies.yaml && ./scripts/test-network.sh   # after:  every check passes
#
# Targets are pod IPs, not names: a pod with no DNS rule could not resolve a
# name, and the test would then show a DNS failure instead of a blocked
# connection. "blocked" means the connection attempt timed out: the packet
# was dropped on the way, so the target never saw it.
set -uo pipefail

NS="restauranty"
HOST="restauranty.aks.springlaughing.dev"
TIMEOUT=5

pass=0; fail=0
result() {  # result <check> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  PASS  %-55s %s\n' "$1" "$3"; pass=$((pass + 1))
  else
    printf '  FAIL  %-55s expected %s, got %s\n' "$1" "$2" "$3"; fail=$((fail + 1))
  fi
}

# The IP of a running pod that is not shutting down. Right after a restart,
# an old pod can still be in the list; it is no longer protected by the
# rules and would answer "connection refused", a false result.
pod_ip() {
  kubectl get pods -n "$NS" -l "app=$1" -o json | jq -r '
    [.items[] | select(.status.phase == "Running" and .metadata.deletionTimestamp == null)]
    | .[0].status.podIP // empty'
}

# Exit code -> result. 0 = connected, 28 = timed out (the packet was
# dropped: blocked). Anything else (refused, reset, ...) is reported as is,
# never as "open" or "blocked".
verdict() {
  case "$1" in
    0)  echo open ;;
    28) echo blocked ;;
    *)  echo "error (exit $1)" ;;
  esac
}

# From an attacker pod (has curl). curl exits 0 on any HTTP answer.
from_attacker() {  # from_attacker <namespace> <ip> <port>
  kubectl exec -n "$1" attacker -- \
    curl -s -o /dev/null --connect-timeout "$TIMEOUT" --max-time $((TIMEOUT + 3)) "http://$2:$3" >/dev/null 2>&1
  verdict $?
}

# From inside an app pod. The app images have node but no curl.
from_app() {  # from_app <deployment> <host> <port>
  kubectl exec -n "$NS" "deploy/$1" -- node -e '
    const s = require("net").connect(+process.argv[2], process.argv[1]);
    s.setTimeout(+process.argv[3] * 1000);
    s.on("connect", () => process.exit(0));
    s.on("timeout", () => process.exit(28));
    s.on("error",   () => process.exit(1));' "$2" "$3" "$TIMEOUT" >/dev/null 2>&1
  verdict $?
}

MONGO=$(pod_ip mongodb); AUTH=$(pod_ip auth)
if [ -z "$MONGO" ] || [ -z "$AUTH" ]; then echo "App pods not found in $NS"; exit 1; fi
for ns in "$NS" default; do
  kubectl get pod attacker -n "$ns" >/dev/null 2>&1 \
    || { echo "No attacker pod in $ns: kubectl apply -f k8s/proof/attacker-pods.yaml"; exit 1; }
done
echo "Policies in $NS: $(kubectl get networkpolicy -n "$NS" -o name | wc -l)"

echo; echo "The app still works"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$HOST/")
result "internet -> Gateway -> client" 200 "$code"
# A wrong password: auth must look the user up in MongoDB to say 401.
# If auth could not reach MongoDB, the answer would be a 500 or a timeout.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST "https://$HOST/api/auth/login" \
  -H 'Content-Type: application/json' -d '{"email":"nobody@example.com","password":"wrong"}')
result "internet -> Gateway -> auth -> MongoDB (wrong login)" 401 "$code"
result "items -> Cloudinary (api.cloudinary.com:443)" open "$(from_app items api.cloudinary.com 443)"

echo; echo "A hacked pod in the app namespace"
result "attacker -> MongoDB :27017" blocked "$(from_attacker "$NS" "$MONGO" 27017)"
result "attacker -> auth :3001" blocked "$(from_attacker "$NS" "$AUTH" 3001)"

echo; echo "A hacked pod in another namespace"
result "attacker (default) -> MongoDB :27017" blocked "$(from_attacker default "$MONGO" 27017)"
result "attacker (default) -> auth :3001" blocked "$(from_attacker default "$AUTH" 3001)"

echo; echo "A hacked app pod"
result "discounts -> auth :3001 (backends do not call each other)" blocked "$(from_app discounts "$AUTH" 3001)"
result "auth -> internet (1.1.1.1:443, no way to send data out)" blocked "$(from_app auth 1.1.1.1 443)"
result "items -> Azure metadata service (169.254.169.254:80)" blocked "$(from_app items 169.254.169.254 80)"

echo; echo "No app ServiceAccount may read Secrets"
for sa in auth discounts items client mongodb; do
  answer=$(kubectl auth can-i get secrets -n "$NS" --as="system:serviceaccount:$NS:$sa" 2>/dev/null)
  result "ServiceAccount $sa: get secrets" no "$answer"
done

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
