#!/usr/bin/env bash
# Sets up Restauranty on the AKS cluster from infra-aks: platform first, then the app.
# Run after the cluster exists, kubectl points at it, and both Terraform layers are applied:
#   cd ~/ironhack/infra-aks/cluster && terraform apply && $(terraform output -raw get_credentials)
#   cd terraform/persistent   && terraform apply   # once: Key Vault, registry, IP, DNS
#   cd terraform/cluster-access && terraform apply # after every rebuild: AcrPull, Network Contributor
#   ./scripts/setup-aks.sh
# Safe to run again: every step installs or updates, nothing fails on "already exists".
set -euo pipefail

CLUSTER="aks-evgenia-k8s-dev"
KEY_VAULT="kv-evgenia-restauranty"
APP_NS="restauranty"
NGF_VERSION="2.8.1"                      # chart and app version; 2.4+ has RateLimitPolicy (#10)
CERT_MANAGER_VERSION="v1.21.3"

cd "$(dirname "$0")/.."
log() { echo; echo "==> $*"; }

for tool in az kubectl helm openssl; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done

# 0. Never run this against another cluster by accident
log "Checking kubectl points at ${CLUSTER}"
CONTEXT=$(kubectl config current-context)
[ "$CONTEXT" = "$CLUSTER" ] || { echo "  current context is '$CONTEXT', not ${CLUSTER}. Stopping."; exit 1; }

# 1. Gateway API CRDs (the version NGF was tested with), then NGINX Gateway Fabric.
log "Installing Gateway API CRDs for NGINX Gateway Fabric ${NGF_VERSION}"
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${NGF_VERSION}" \
  | kubectl apply --server-side -f -

log "Installing NGINX Gateway Fabric ${NGF_VERSION}"
helm upgrade --install nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version "$NGF_VERSION" \
  --namespace nginx-gateway --create-namespace \
  -f k8s/platform/nginx-gateway-fabric-values.yaml \
  --wait --timeout=5m

# 2. cert-manager, after the Gateway API CRDs (it only watches Gateway objects
#    if they exist when it starts).
log "Installing cert-manager ${CERT_MANAGER_VERSION}"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update jetstack >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "$CERT_MANAGER_VERSION" \
  --namespace cert-manager --create-namespace \
  -f k8s/platform/cert-manager-values.yaml \
  --wait --timeout=5m

# 3. Platform: namespaces, storage, the Gateway, Let's Encrypt
log "Applying platform manifests"
kubectl apply -f k8s/platform/namespaces.yaml
kubectl apply -f k8s/platform/storageclass.yaml
kubectl apply -f k8s/platform/gateway.yaml
for _ in $(seq 1 12); do                 # cert-manager's webhook may need a few seconds
  kubectl apply -f k8s/platform/cluster-issuers.yaml && break
  echo "  cert-manager webhook not ready yet, retrying in 5 s"
  sleep 5
done
kubectl apply -f k8s/platform/certificate.yaml

# 4. Secrets: Key Vault -> one Kubernetes Secret per workload, each with only
#    what that workload needs. Temporary: #8 replaces this step with External
#    Secrets and one Azure identity per service, and keeps the same Secret
#    names, so the Deployments do not change.
#    Values are passed through files (process substitution), never as command
#    arguments, so they never show up in `ps` or the shell history.
log "Secrets from Key Vault ${KEY_VAULT}"
kv() { az keyvault secret show --vault-name "$KEY_VAULT" -n "$1" --query value -o tsv; }
kv_exists() { az keyvault secret show --vault-name "$KEY_VAULT" -n "$1" >/dev/null 2>&1; }

# The MongoDB root password has no other home: create it once if it is missing.
if ! kv_exists mongo-root-password; then
  echo "  mongo-root-password missing in Key Vault, generating one"
  az keyvault secret set --vault-name "$KEY_VAULT" -n mongo-root-password \
    --file <(openssl rand -hex 32 | tr -d '\n') --output none
fi
# The app password goes into the MongoDB URL, so it must need no URL escaping.
if ! kv mongo-password | grep -qE '^[0-9a-f]+$'; then
  echo "  mongo-password in Key Vault is not hex: it would break MONGODB_URI. Replace it with:"
  echo "    az keyvault secret set --vault-name $KEY_VAULT -n mongo-password --file <(openssl rand -hex 32 | tr -d '\\n') --output none"
  exit 1
fi

apply_secret() {   # apply_secret <name> --from-file=key=<(...) ...
  local name=$1; shift
  kubectl create secret generic "$name" -n "$APP_NS" "$@" --dry-run=client -o yaml | kubectl apply -f -
}
apply_secret mongodb-secrets \
  --from-file=root-password=<(kv mongo-root-password | tr -d '\n') \
  --from-file=app-password=<(kv mongo-password | tr -d '\n')
apply_secret auth-secrets \
  --from-file=mongo-password=<(kv mongo-password | tr -d '\n') \
  --from-file=jwt-private-key=<(kv jwt-private-key)
apply_secret discounts-secrets \
  --from-file=mongo-password=<(kv mongo-password | tr -d '\n') \
  --from-file=jwt-public-key=<(kv jwt-public-key)
# Cloudinary: added once its secrets exist in Key Vault. items starts without
# them, but creating an item always uploads an image, so that fails until then.
if kv_exists cloud-name; then
  apply_secret items-secrets \
    --from-file=mongo-password=<(kv mongo-password | tr -d '\n') \
    --from-file=jwt-public-key=<(kv jwt-public-key) \
    --from-file=cloud-name=<(kv cloud-name | tr -d '\n') \
    --from-file=cloud-api-key=<(kv cloud-api-key | tr -d '\n') \
    --from-file=cloud-api-secret=<(kv cloud-api-secret | tr -d '\n')
else
  echo "  no Cloudinary secrets in Key Vault: items starts, but creating an item fails"
  apply_secret items-secrets \
    --from-file=mongo-password=<(kv mongo-password | tr -d '\n') \
    --from-file=jwt-public-key=<(kv jwt-public-key)
fi

# 5. The app: MongoDB first, then the four components and the routes
log "Applying the app"
kubectl apply -f k8s/app/mongodb.yaml
kubectl rollout status statefulset/mongodb -n "$APP_NS" --timeout=5m
kubectl apply -f k8s/app/
# A changed Secret does not restart running pods by itself
kubectl rollout restart deployment -n "$APP_NS"
for d in auth discounts items client; do
  kubectl rollout status "deployment/$d" -n "$APP_NS" --timeout=5m
done

# 6. Where things stand
log "Status"
kubectl get gateway -n gateway
kubectl get svc -n gateway
kubectl get certificate -n gateway
kubectl get pods -n "$APP_NS" -o wide
echo
echo "Certificate READY=False for a few minutes is normal (Let's Encrypt checks port 80)."
echo "Then: curl -I https://restauranty.aks.springlaughing.dev  (staging: add -k)"
