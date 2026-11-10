#!/usr/bin/env bash
# Sets up Restauranty on the AKS cluster from infra-aks: platform first, then the app.
# Run after the cluster exists, kubectl points at it, and both Terraform layers are applied:
#   cd ~/ironhack/infra-aks/cluster && terraform apply && $(terraform output -raw get_credentials)
#   cd terraform/persistent   && terraform apply   # once: Key Vault, registry, IP, DNS
#   cd terraform/cluster-access && terraform apply # after every rebuild: AcrPull, Network Contributor,
#                                                  # per-workload identities (federated credentials)
#   ./scripts/setup-aks.sh
# Safe to run again: every step installs or updates, nothing fails on "already exists".
set -euo pipefail

CLUSTER="aks-evgenia-k8s-dev"
KEY_VAULT="kv-evgenia-restauranty"
APP_NS="restauranty"
NGF_VERSION="2.8.1"                      # chart and app version; 2.4+ has RateLimitPolicy (#10)
CERT_MANAGER_VERSION="v1.21.3"
EXTERNAL_SECRETS_VERSION="2.14.0"
RELOADER_VERSION="2.2.18"

TLS_BACKUP="restauranty-tls-backup"      # Key Vault secret: copy of the HTTPS certificate Secret

cd "$(dirname "$0")/.."
log() { echo; echo "==> $*"; }
kv() { az keyvault secret show --vault-name "$KEY_VAULT" -n "$1" --query value -o tsv; }
kv_exists() { az keyvault secret show --vault-name "$KEY_VAULT" -n "$1" >/dev/null 2>&1; }

for tool in az kubectl helm openssl jq; do
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
# After a rebuild, put the saved certificate back BEFORE cert-manager sees the
# Certificate. A valid Secret with matching names and issuer means cert-manager
# issues nothing, so a rebuild does not use up Let's Encrypt's limit of 5
# production certificates per week. An expired copy is simply renewed.
if ! kubectl get secret restauranty-tls -n gateway >/dev/null 2>&1 && kv_exists "$TLS_BACKUP"; then
  echo "  restoring the HTTPS certificate from Key Vault"
  kv "$TLS_BACKUP" | kubectl apply -f -
fi
kubectl apply -f k8s/platform/certificate.yaml

# 4. External Secrets (Key Vault -> Kubernetes Secrets, one Azure identity per
#    workload) and Reloader (restart a Deployment when its Secret changes).
#    Reloader needs the restauranty namespace to exist (step 3): it gets a
#    Role there instead of cluster-wide rights.
log "Installing External Secrets ${EXTERNAL_SECRETS_VERSION} and Reloader ${RELOADER_VERSION}"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo add stakater https://stakater.github.io/stakater-charts >/dev/null 2>&1 || true
helm repo update external-secrets stakater >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version "$EXTERNAL_SECRETS_VERSION" \
  --namespace external-secrets --create-namespace \
  -f k8s/platform/external-secrets-values.yaml \
  --wait --timeout=5m
helm upgrade --install reloader stakater/reloader \
  --version "$RELOADER_VERSION" \
  --namespace reloader --create-namespace \
  -f k8s/platform/reloader-values.yaml \
  --wait --timeout=5m

# 5. Key Vault checks. The values themselves now reach the cluster only through
#    External Secrets; this step only makes sure they exist and are usable.
log "Checking secrets in Key Vault ${KEY_VAULT}"

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

# items' ExternalSecret asks for the Cloudinary keys; without them it cannot sync.
if ! kv_exists cloud-name; then
  echo "  Cloudinary secrets missing in Key Vault: items-secrets will not sync. Add them first (see docs/build-log.md)."
  exit 1
fi

# One-time move: Secrets created by the old version of this script (before
# #8) are not owned by an ExternalSecret, and External Secrets will not take
# over a Secret it did not create. Delete them; External Secrets writes them
# again within seconds. Running pods keep their values; nothing restarts.
for s in mongodb-secrets auth-secrets discounts-secrets items-secrets; do
  owner=$(kubectl get secret "$s" -n "$APP_NS" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)
  if kubectl get secret "$s" -n "$APP_NS" >/dev/null 2>&1 && [ "$owner" != "ExternalSecret" ]; then
    echo "  $s was made by hand: handing it over to External Secrets"
    kubectl delete secret "$s" -n "$APP_NS"
  fi
done

# 6. The app: MongoDB first, then the four components and the routes.
#    Each file brings its own ServiceAccount, SecretStore and ExternalSecret.
#    A pod whose Secret is not there yet waits (CreateContainerConfigError)
#    and starts as soon as External Secrets has written it.
log "Applying the app"
kubectl apply -f k8s/app/mongodb.yaml
kubectl wait externalsecret/mongodb-secrets -n "$APP_NS" --for=condition=Ready --timeout=3m
kubectl rollout status statefulset/mongodb -n "$APP_NS" --timeout=5m
kubectl apply -f k8s/app/
kubectl wait externalsecret --all -n "$APP_NS" --for=condition=Ready --timeout=3m
kubectl get externalsecret -n "$APP_NS"
# No restart here: Reloader restarts a Deployment only when its Secret's
# content really changes.
for d in auth discounts items client; do
  kubectl rollout status "deployment/$d" -n "$APP_NS" --timeout=5m
done

# Network rules: default deny, then only the paths the app uses (#11).
# Test them with scripts/test-network.sh.
log "Applying the network rules"
kubectl apply -f k8s/network/

# 7. Save the HTTPS certificate in Key Vault, so the next rebuild can restore it
#    (step 3). Only the parts cert-manager checks are kept; saved again only
#    when the certificate changed (first issue or renewal).
log "Backing up the HTTPS certificate"
if kubectl wait certificate/restauranty-tls -n gateway --for=condition=Ready --timeout=3m >/dev/null; then
  live_crt=$(kubectl get secret restauranty-tls -n gateway -o jsonpath='{.data.tls\.crt}')
  saved_crt=$(kv "$TLS_BACKUP" 2>/dev/null | jq -r '.data["tls.crt"] // empty' || true)
  if [ "$live_crt" = "$saved_crt" ]; then
    echo "  unchanged, backup kept"
  else
    az keyvault secret set --vault-name "$KEY_VAULT" -n "$TLS_BACKUP" --output none --file <(
      kubectl get secret restauranty-tls -n gateway -o json | jq -c '{
        apiVersion, kind, type, data,
        metadata: { name: .metadata.name, namespace: .metadata.namespace,
                    labels: .metadata.labels, annotations: .metadata.annotations } }')
    echo "  saved to Key Vault as ${TLS_BACKUP}"
  fi
else
  echo "  certificate not ready yet: run this script again later to back it up"
fi

# 8. Where things stand
log "Status"
kubectl get gateway -n gateway
kubectl get svc -n gateway
kubectl get certificate -n gateway
kubectl get pods -n "$APP_NS" -o wide
echo
echo "Open: https://restauranty.aks.springlaughing.dev"
