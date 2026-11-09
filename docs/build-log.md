# Build log: Restauranty DevSecOps on AKS

**What this is.** A day-by-day record of what was built and why. Each entry has the goal, the commands, and the result, so the work can be followed or repeated later. It sits next to the [security assessment](security-assessment.md), which explains the problems; this log shows the fixes being built.

**How to read it.** Entries are in order. Each one starts with its result in one line. You can read any entry on its own.

**All work below is from 9 November 2026.**

---

## Contents

- [Part 1 — assessment and code fixes](#part-1--assessment-and-code-fixes)
  - [1. Run the app locally](#1-run-the-app-locally)
  - [2. Security assessment](#2-security-assessment)
  - [3. Code fix: RS256 signing and the JWT key pair](#3-code-fix-rs256-signing-and-the-jwt-key-pair)
  - [4. Code fix: 401 instead of 500, and brief errors](#4-code-fix-401-instead-of-500-and-brief-errors)
  - [5. Code fix: one login answer](#5-code-fix-one-login-answer)
  - [6. Code fix: no password hashes, no personal data in logs](#6-code-fix-no-password-hashes-no-personal-data-in-logs)
  - [7. Code fix: a login token on every data route](#7-code-fix-a-login-token-on-every-data-route)
- [Part 2 — infrastructure](#part-2--infrastructure)
  - [8. Module: enforce NetworkPolicies with Cilium](#8-module-enforce-networkpolicies-with-cilium)
  - [9. Cluster: AKS up](#9-cluster-aks-up)
  - [10. Persistent layer: Key Vault, registry, IP, identity](#10-persistent-layer-key-vault-registry-ip-identity)
- [Findings and their fixes](#findings-and-their-fixes)
- [What is next](#what-is-next)

---

## Part 1 — assessment and code fixes

Goal for the day: test the app as received, then fix the code findings before putting anything on the internet.

### 1. Run the app locally

**Result:** the whole app runs on the laptop. MongoDB and HAProxy in Docker, the three backends with `node`, the React client with `npm start`.

```bash
# MongoDB
docker run -d --name restauranty-mongo -p 27017:27017 -v restauranty-mongo-data:/data/db mongo:8

# One .env per backend, from the example
for s in auth discounts items; do cp backend/$s/.env.example backend/$s/.env; done

# Each backend in its own terminal
cd backend/auth && node server.js
cd backend/discounts && node server.js
cd backend/items && node server.js

# Client
cd client && npm install && BROWSER=none PORT=3000 npm start

# HAProxy in Docker on port 80 (its config reaches the host backends)
docker run -d --name restauranty-haproxy -p 80:80 \
  --add-host host.docker.internal:host-gateway \
  -v <local haproxy.cfg>:/usr/local/etc/haproxy/haproxy.cfg:ro haproxy:3.0-alpine
```

The app is then at http://localhost. One fix was needed first: `client/package-lock.json` was out of sync, so `npm install` resynced it.

### 2. Security assessment

**Result:** 20 findings (8 high, 9 medium, 3 low), each proved with a real request. Full write-up in [security-assessment.md](security-assessment.md).

The testing followed the OWASP Web Security Testing Guide, step by step: list every route, then try each one the way an attacker would (no token, a changed token, a forged token, bad input). The three worst findings:

1. Anyone could read every user's password hash and personal data without logging in (F11).
2. Anyone could make an admin token, because the signing secret was published in the repo (F9).
3. Anyone could change or delete any data without a token (F13, F14).

### 3. Code fix: RS256 signing and the JWT key pair

**Result:** tokens are signed with a key pair instead of one shared secret. Only `auth` can create tokens; `discounts` and `items` can only check them. (Fixes F9.)

**The problem.** The app used HS256: one secret both signs and checks tokens. That secret was `MySecret1!`, published in `.env.example`. Anyone could sign an admin token.

**Create the key pair** (local development only; the files are git-ignored):

```bash
# Private key: signs tokens. Public key: checks tokens.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt-private.pem
openssl pkey -in jwt-private.pem -pubout -out jwt-public.pem
```

**Put the keys in the .env files** (auth gets the private key; discounts and items get the public key):

```bash
# set_key <.env file> <variable> <pem file>: writes the key on one line
set_key() {
  grep -v "^$2=" "$1" > "$1.tmp"
  printf '%s="%s"\n' "$2" "$(awk '{printf "%s\\n", $0}' "$3")" >> "$1.tmp"
  mv "$1.tmp" "$1"
}
set_key backend/auth/.env      JWT_PRIVATE_KEY jwt-private.pem
set_key backend/discounts/.env JWT_PUBLIC_KEY  jwt-public.pem
set_key backend/items/.env     JWT_PUBLIC_KEY  jwt-public.pem
```

**In the code:** each service loads its key at startup (`backend/*/config/jwt.js`) and refuses to start without a valid one. `auth` signs with `RS256`, an issuer and an audience; every service checks all three.

**How keys are handled later:** on AKS the keys come from Azure Key Vault, not from `.env` files (see entry 10). In real production you would not manage the key at all: an identity provider (Entra External ID, Keycloak) would hold it and publish the public key at a JWKS URL, and rotate it automatically.

**Proof:** a token forged with the old secret was accepted before, refused (401) after. Retest 1 in the assessment.

### 4. Code fix: 401 instead of 500, and brief errors

**Result:** a bad token gets "401 not allowed", not "500 server error". Bad input gets a short message, not the raw database error. (Fixes F8, F17.)

- Token errors: the shared error handler (`backend/*/error-handling/index.js`) answers 401 and writes one short log line, so attacks no longer look like server outages.
- Input errors: 32 route handlers used to send the whole database error (model and field names). They now pass the error on, and the handler answers `Invalid id` or `Invalid or missing fields`. The details go only to the log.

### 5. Code fix: one login answer

**Result:** login gives the same answer whether or not the email exists, so it no longer reveals which emails have an account. (Fixes F4.)

Before: an unknown email got "User not found." (fast), a wrong password got "Email or Password Incorrect" (slow). Now both get the same message, and an unknown email is still checked against a dummy hash so the response takes the same time.

### 6. Code fix: no password hashes, no personal data in logs

**Result:** no answer contains a password hash, and the logs no longer contain personal data. (Fixes F11, F14, F15, F3.)

- The User model hides the `password` field by default and strips it from every answer. Login is the only query that loads it.
- The `console.log` lines that wrote token content (email, address, phone) and whole records were removed.

PRs #22 covered entries 3 to 6. Each fix is one commit.

### 7. Code fix: a login token on every data route

**Result:** every data route in discounts and items now requires a valid token, and the frontend sends the token. (Fixes F12, F13; the brief's own task, #9.)

- The token check runs where the routes are mounted (`backend/*/app.js`), so a new route is protected automatically. Health checks, `/metrics`, signup and login stay public on purpose.
- The frontend adds the token to every call to our own API, through one axios interceptor (`client/src/services/apiToken.js`).

**Proof:** every data route answered 401 without a token; the admin pages still work. Retest 2 in the assessment. PR #23.

---

## Part 2 — infrastructure

Goal for the day: the app on AKS. Build the cluster and the resources that outlive it.

### 8. Module: enforce NetworkPolicies with Cilium

**Result:** the shared AKS module can now enforce Kubernetes NetworkPolicies. Released as `terraform-azure-modules` v1.4.0.

**Why.** Without a policy engine, Kubernetes accepts NetworkPolicies but nothing enforces them. The attacker-pod test would then silently pass. The module gained two settings, `network_data_plane` and `network_policy`; setting both to `cilium` enforces policies. A safety check refuses a half-configuration. Four new tests, all passing.

### 9. Cluster: AKS up

**Result:** a 3-node AKS cluster is running in Germany West Central, with Cilium enforcing policies.

```bash
cd ~/ironhack/infra-aks/cluster
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init -upgrade
terraform plan -out restauranty.tfplan   # review: 8 to add
terraform apply restauranty.tfplan

# Connect and check
az aks get-credentials -g rg-evgenia-k8s-dev -n aks-evgenia-k8s-dev
kubectl get nodes -o wide                         # 3 nodes Ready, Standard_D2s_v3
kubectl -n kube-system get ds -l k8s-app=cilium   # cilium 3/3 ready
```

Settings: 3 × `Standard_D2s_v3` over zones 1-3, Kubernetes 1.36, Azure CNI Overlay with Cilium, OIDC issuer and Workload Identity on. The cluster lives in the separate `infra-aks` repo and is reused, not rebuilt from scratch.

### 10. Persistent layer: Key Vault, registry, IP, identity

**Result:** the Terraform for the resources that must survive a daily cluster rebuild is written and planned. Lives in `terraform/persistent/` in this repo.

**Why a separate layer.** A Key Vault, the images and the domain's IP must not be destroyed when the cluster is. They have their own Terraform root, so `terraform destroy` on the cluster never touches them.

```bash
cd terraform/persistent
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform plan -out persistent.tfplan   # review: 7 to add
terraform apply persistent.tfplan
```

It creates: Key Vault (RBAC, soft delete), a container registry (Basic), a static public IP, and the pipeline identity, plus two role assignments (operator may write secrets, pipeline may push images).

**Put the secret values in by hand** (so no secret is ever in Terraform state):

```bash
KV=$(terraform output -raw key_vault_name)
az keyvault secret set --vault-name "$KV" --name jwt-private-key --file jwt-private.pem
az keyvault secret set --vault-name "$KV" --name jwt-public-key  --file jwt-public.pem
az keyvault secret set --vault-name "$KV" --name mongo-password  --value '<a strong password>'
```

Per-service identities and their Key Vault roles come next (#8), in a `cluster-access` layer that reads this one.

---

## Findings and their fixes

The 20 findings from the [security assessment](security-assessment.md), and whether each is fixed yet. "Fixed" means the code change is done and retested locally; the AKS parts (Gateway block, rate limit, Key Vault) are marked where they belong.

| ID | Finding | Severity | State |
| --- | --- | --- | --- |
| F1 | Every new account is admin | High | Accepted (demo shortcut, documented) |
| F2 | Personal data inside the token | Medium | Accepted (profile page reads it) |
| F3 | Personal data in the server log | Medium | **Fixed** (entry 6) |
| F4 | Login reveals which emails exist | Medium | **Fixed** (entry 5) |
| F5 | Weak passwords accepted | Medium | Accepted (other fixes reduce the risk) |
| F6 | No limit on login attempts | High | Planned on AKS: Gateway rate limit (#10) |
| F7 | Logout does not end the session | Medium | Accepted (6-hour token) |
| F8 | Token errors answered with 500 | Medium | **Fixed** (entry 4) |
| F9 | Public signing secret, one secret for all | High | **Fixed** (entry 3) |
| F10 | Old `.env` files in git history | Low | Planned: gitleaks in the pipeline (#13) |
| F11 | User list with hashes, no login | High | **Fixed** (entries 6, 7) |
| F12 | All data readable without login | Medium | **Fixed** (entry 7) |
| F13 | All data changeable without login | High | **Fixed** (entry 7) |
| F14 | Any user deleted without login | High | **Fixed** (entries 6, 7) |
| F15 | Logged-in users get every hash | High | **Fixed** (entry 6) |
| F16 | Any discount and any dates accepted | Medium | Accepted (closed to strangers by #9) |
| F17 | Raw database errors in answers | Low | **Fixed** (entry 4) |
| F18 | Metrics labelled with the full URL | Medium | Planned: label by route (#14) |
| F19 | Outdated packages | Low | Planned: hardened images (#5) |
| F20 | Cloudinary keys in git history | High | Not reported (course repo, keys not used) |

Fixed so far: 10 of 20, all the code findings. The rest are either planned for AKS or accepted on purpose.

---

## What is next

| Task | Issue |
| --- | --- |
| Apply the persistent layer; put the secrets in Key Vault | #6 |
| Hardened Dockerfiles (non-root, no dev tools) and docker-compose | #5, #1 |
| Manifests, MongoDB, Gateway routing, HTTPS | #7 |
| Per-service identities, External Secrets, NetworkPolicies | #8, #11 |
| Gateway block on the user list, login rate limit | #10 |
| Pipeline with security gates | #12, #13 |
| Monitoring, alerts, the attack demo | #14, #15 |
