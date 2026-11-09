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
- [Part 3 — container images](#part-3--container-images)
  - [11. Hardened Dockerfiles for all four components](#11-hardened-dockerfiles-for-all-four-components)
  - [What is Trivy, and why we scan](#what-is-trivy-and-why-we-scan)
  - [The software supply chain](#the-software-supply-chain)
- [Part 4 — the app on AKS](#part-4--the-app-on-aks)
  - [12. Cluster access: image pulls and the static IP](#12-cluster-access-image-pulls-and-the-static-ip)
  - [13. DNS: the app's names point at the static IP](#13-dns-the-apps-names-point-at-the-static-ip)
  - [14. MongoDB password made URL-safe](#14-mongodb-password-made-url-safe)
  - [15. Kubernetes manifests, Gateway and HTTPS](#15-kubernetes-manifests-gateway-and-https)
  - [What was created in Part 4](#what-was-created-in-part-4)
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
az keyvault secret set --vault-name "$KV" --name mongo-password  --file <(openssl rand -hex 32 | tr -d '\n')
```

The MongoDB password is hex because it goes inside a URL (see entry 14).

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
| F19 | Outdated packages | Low | **Images done** (entry 11): 0 high/critical; pipeline scan still to add (#13) |
| F20 | Cloudinary keys in git history | High | Not reported (course repo, keys not used) |

Fixed so far: 10 of 20, all the code findings. The rest are either planned for AKS or accepted on purpose.

---

## Part 3 — container images

### 11. Hardened Dockerfiles for all four components

**Result:** each component now has a container image that runs as a non-root user and has no known high or critical vulnerabilities. (Issue #5; part of F19.)

**Why.** The app will run as containers on AKS. A container built carelessly runs as root, ships development tools, and uses a base image full of outdated libraries. Each of those is a way in for an attacker. These images avoid all three.

**The backends** (`backend/*/Dockerfile`): two stages. The first installs only the production dependencies. The second copies them into a small image with the app. It runs `node server.js` (not `nodemon`, a development tool), as the built-in non-root user, and `npm` is removed from the final image so its own vulnerabilities are gone.

**The client** (`client/Dockerfile`): the React site is built with Node, then served by `nginx-unprivileged`, which runs as a non-root user on port 8080. The base image's operating-system packages are upgraded, which cleared outdated `libssl`, `libcrypto` and `brotli`.

```bash
# Build an image
docker build -t restauranty-auth ./backend/auth

# Check it runs as a non-root user
docker run --rm --entrypoint sh restauranty-auth -c id   # uid=1000(node)
```

A `.dockerignore` in each folder keeps `.env` files, the JWT keys, `node_modules` and git history out of the image.

### What is Trivy, and why we scan

**In one line:** Trivy is a free tool that checks a container image for known security problems before it ships.

**What it is.** Trivy is a real, widely used open-source scanner made by Aqua Security. It is one of the most common tools of its kind and runs in the pipelines of many companies. It scans container images, code folders and infrastructure files.

**What it looks for.** Mainly **known vulnerabilities** (called CVEs). Every image contains many pieces of software: operating-system packages (like `libssl`) and application packages (from `package-lock.json`). Each has a version. Security researchers keep public lists of which versions have known problems. Trivy compares every package in the image against those lists and reports any match, with how serious it is and which version fixes it.

**Why we use it.** An image can be built from perfectly fine code and still be dangerous, because a library inside it is old and has a known hole. A person cannot track thousands of packages by hand. Trivy does it in seconds, so a problem is caught before the image reaches the cluster.

**How it becomes a gate.** In the pipeline (planned, #13), Trivy runs on every build and **fails the build if it finds a CRITICAL problem**. So a dangerous image never gets deployed. We block on CRITICAL only, not on everything, so the gate stays useful and is not switched off from noise.

**What it found here.** The backend images had no critical problems. The client image first showed 3 critical and 62 high problems, all in the base image's operating-system packages. Upgrading those packages in the image cleared them.

```bash
# Scan an image for the serious problems, the way the pipeline will
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity HIGH,CRITICAL restauranty-client
```

| Image | High / critical before | After |
| --- | --- | --- |
| auth, discounts, items | 0 critical, 10 high (in npm) | **0** (npm removed) |
| client | 3 critical, 62 high (in the base OS) | **0** (OS packages upgraded) |

Trivy is one of three tools in this project, each for a different job: Trivy for vulnerable packages in images, Semgrep for risky code patterns, gitleaks for secrets in git history (see the [security assessment](security-assessment.md), step 8).

### The software supply chain

**In one line:** the path a piece of software travels from source code to running in the cluster, and being able to trust every step of it.

**The official names.** This has real terms, used across the industry:

| Term | What it means |
| --- | --- |
| **Software supply chain** | The whole path from code to a running program: the source, the libraries it pulls in, the build, the image, the registry, the cluster. |
| **Software supply chain security** | Making every step of that path trustworthy and checked. |
| **Provenance** | A record of how an artifact was built and from which exact code, so its origin can be proven. |
| **SBOM** (Software Bill of Materials) | A list of everything inside an image: every library and its version. Like an ingredients list on food. |
| **SLSA** (said "salsa") | A public framework from the OpenSSF that grades how trustworthy a build is, in levels. |
| **A03 Software Supply Chain Failures** | The matching category in the OWASP Top 10 2025. Findings F10, F19 and F20 sit here. |

**Why it matters.** Most attacks no longer break in through the running app. They slip something bad in earlier: a poisoned library, a tampered image, a secret left in git. If each step is checked and traceable, a bad artifact is caught before it runs, and when something does go wrong, it can be traced back to where it came from.

**Our chain, link by link.** For the image tag `client:bfb0e27`:

| Step | What it is | What makes it trusted or traceable |
| --- | --- | --- |
| Source | Commit `bfb0e27` on `main` | Reached only through pull requests; gitleaks will scan every push for secrets (#13) |
| Dependencies | The libraries in `package-lock.json` | Exact versions pinned; `npm audit` checks them (#13) |
| Build | The hardened Dockerfile | Non-root, no dev tools, minimal base |
| Scan | Trivy on the built image | 0 high or critical; the pipeline blocks on critical (#13) |
| Name | The tag `bfb0e27` | The commit SHA, so the image points back to exact code |
| Store | The private registry | Reached only with short-lived identity tokens, no stored password |
| Run | The AKS cluster (next) | Only images from this registry; the kubelet identity needs AcrPull |

Every link names where the code came from, what went into it, and who may touch it. That end-to-end trust is what "software supply chain security" means.

**What a stricter setup would add** (next steps, not this week): **signing** each image so the cluster only runs images signed by the pipeline (for example with cosign), an **SBOM** stored next to each image, and **verified provenance** that proves the image was built by the pipeline from that commit. These raise the SLSA level.

---

## Part 4 — the app on AKS

Goal: the app running on the cluster at https://restauranty.aks.springlaughing.dev, with a real HTTPS certificate. Issue #7, branch `7-manifests-gateway-https`.

**Three Terraform layers, three lifetimes.** This part adds the third layer. Each layer has its own folder and state, so destroying one never touches another.

| Layer | Folder | Lifetime | Holds |
| --- | --- | --- | --- |
| Persistent | `terraform/persistent/` (this repo) | Never destroyed | Key Vault, registry, static IP, DNS records, pipeline identity |
| Cluster | `infra-aks/cluster` (separate repo) | Destroyed and rebuilt | The AKS cluster itself |
| Cluster access | `terraform/cluster-access/` (this repo, new) | Applied again after every rebuild | What the cluster may do in Azure |

### 12. Cluster access: image pulls and the static IP

**Result:** the cluster may pull images from our registry and may use our static IP. Two role assignments, applied. Lives in `terraform/cluster-access/`.

**Why two permissions.**

- **AcrPull for the kubelet.** The kubelet is the agent on each node that starts containers. Our registry has no password login (admin user off), so the kubelet signs in with its own Azure identity. Without AcrPull, every pod fails with `ImagePullBackOff`. The role is pull only: the cluster can never push or change an image.
- **Network Contributor for the cluster's identity, on the persistent resource group only.** The static IP lives in `rg-evgenia-restauranty`, not in the cluster's own resource group. Azure lets a load balancer use an IP only if its owner may "join" that IP. The scope is that one group, not the whole subscription.

**Why a separate layer.** A rebuilt cluster gets new identities, so these roles must be created again after every rebuild. Keeping them here, and not in the shared `infra-aks` repo, keeps Restauranty's permissions out of the voting app's cluster code. The layer only *reads* the cluster, registry and resource group (data sources), so `terraform destroy` here removes the two roles and nothing else.

```bash
cd terraform/cluster-access
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform plan -out access.tfplan   # review: 2 to add
terraform apply access.tfplan
```

Per-service identities for Key Vault come into this same layer next (#8).

### 13. DNS: the app's names point at the static IP

**Result:** `restauranty.aks.springlaughing.dev` and `grafana.aks.springlaughing.dev` both resolve to `4.182.101.186`. Two A records, applied. Lives in `terraform/persistent/dns.tf`.

**Why in the persistent layer.** The IP never changes, so the records never need to change either. They are set once and survive every cluster rebuild. This also matters for HTTPS: Let's Encrypt checks the name before it issues a certificate, and a stale record would make that check fail.

**The zone is reused from the vote app on AKS.** The zone `aks.springlaughing.dev` was made for the vote app's AKS run, which used the name `vote.aks.springlaughing.dev`. Its teardown deleted the `vote` record, but the zone and its delegation at Porkbun stayed. A zone can hold many names, so Restauranty just adds its own two names next to where `vote` was. Reusing it saved a step: a new zone gets four new name servers, which have to be entered at Porkbun by hand.

```
springlaughing.dev                 your domain, at Porkbun
└── aks.springlaughing.dev         zone in Azure (made for the vote app on AKS)
    ├── vote         (deleted)     the vote app on AKS
    ├── restauranty  → 4.182.101.186
    └── grafana      → 4.182.101.186
```

**The zone is only read.** The zone belongs to the `infra-aks/dns` project. Here it is a data source, so `terraform destroy` removes only our two records, never the zone or the voting app's records.

**Why `grafana` already.** Grafana comes later (#14, #17), but its name is in the same certificate (entry 15). One certificate for both names now means no second issue later.

```bash
cd terraform/persistent
terraform plan -out persistent.tfplan   # review: 2 to add
terraform apply persistent.tfplan
dig +short restauranty.aks.springlaughing.dev   # 4.182.101.186
```

### 14. MongoDB password made URL-safe

**Result:** `mongo-password` in Key Vault is now 64 hex characters. A new secret, `mongo-root-password`, is created by the setup script on its first run.

**Why two MongoDB passwords.** They belong to two different users. `mongo-password` is for `restauranty`, the user the three backends log in as; it may only read and write the app's own database. `mongo-root-password` is for `root`, the administrator, used only for admin work like rotating the app password (#16). No app gets the root password, so a hacked backend cannot create users or touch other databases. The script generates the root password straight into Key Vault (only if it is missing), so it is never typed, printed or stored anywhere else.

**Why.** The apps connect with a URL that contains the password: `mongodb://restauranty:<password>@mongodb:27017/restauranty`. The old value had characters such as `/` or `+`, which have a meaning inside a URL and break it. Hex uses only `0-9` and `a-f`, so it never needs escaping. Nothing used the old value yet, and Key Vault keeps it as an older version.

```bash
az keyvault secret set --vault-name kv-evgenia-restauranty -n mongo-password \
  --file <(openssl rand -hex 32 | tr -d '\n') --output none
```

`--file <(...)` hands the value over as a temporary file, not as a command argument, so it never shows up in the process list or the shell history.

### 15. Kubernetes manifests, Gateway and HTTPS

**Result:** the app runs on AKS at https://restauranty.aks.springlaughing.dev, behind the static IP, with a Let's Encrypt **staging** certificate. Sign-up, login and token checks work end to end. Creating an item waits for the Cloudinary keys.

**What runs where.**

| Namespace | What runs there | Why separate |
| --- | --- | --- |
| `nginx-gateway` | The NGINX Gateway Fabric controller | Installed by Helm; turns Gateway objects into NGINX config |
| `cert-manager` | cert-manager | Installed by Helm; gets and renews certificates |
| `gateway` | The Gateway's NGINX pods, the certificate and its private key | No app pod runs here, so no app has a reason to read the TLS key (threat model, TB1) |
| `restauranty` | auth, discounts, items, client, MongoDB | The app |

**The Gateway** (`k8s/platform/gateway.yaml`) is the only way in from the internet. It has three listeners:

- **port 80**: serves only the Let's Encrypt check and a permanent redirect to HTTPS. Plain HTTP is never served.
- **port 443 for `restauranty`**: routes by path, the same split as `haproxy.cfg` locally: `/api/auth`, `/api/discounts`, `/api/items` to the three backends, everything else to the client.
- **port 443 for `grafana`**: ready for Grafana later.

The HTTPS listeners accept routes only from namespaces labelled `gateway-access: "true"`, so a stray route in any other namespace cannot publish a service. Two annotations on the Gateway tell Azure to put the static IP from entry 12 on its load balancer.

**Why NGINX Gateway Fabric.** It is the same controller as the voting app, so the setup is known. Version 2.4 added `RateLimitPolicy`, which the login rate limit needs (#10). Raw NGINX config snippets stay switched off: a snippet can do anything NGINX can, so it could get around every other rule.

**Why `externalTrafficPolicy: Local`.** Azure then sends traffic only to nodes that run an NGINX pod, so NGINX sees the visitor's real IP. Without it, NGINX sees a node's IP, and a per-IP login limit (#10) would count all visitors as a few addresses.

**HTTPS** (`k8s/platform/cluster-issuers.yaml`, `certificate.yaml`). cert-manager gets a free certificate from Let's Encrypt. To prove we own the name, Let's Encrypt fetches a file from `http://<name>/.well-known/acme-challenge/...`, and cert-manager answers through the Gateway's port 80 (HTTP-01). This needs no write rights in the DNS zone. **Staging first**: the staging certificate is not trusted by browsers, but its limits are generous. Production allows only 5 certificates for the same names per week, so it is used only once staging works. A new private key is made at every renewal.

**MongoDB** (`k8s/app/mongodb.yaml`). One pod, data on a zone-redundant Azure disk (`k8s/platform/storageclass.yaml`). The disk keeps three copies in three zones, so MongoDB can move to another zone if a node dies. Two users, created on the first start:

| User | Rights | Who has the password |
| --- | --- | --- |
| `root` | Everything | Only Key Vault and the MongoDB pod; used for admin work like password rotation (#16) |
| `restauranty` | Read and write on the `restauranty` database only | The three backends |

So a hacked backend cannot create users, change rights or read other databases (threat model, TB3).

**Why MongoDB in the cluster, not Atlas.** The planned tests need it here. A NetworkPolicy can only keep an attacker pod away from a database that runs inside the cluster (#11), and the rotation demo needs admin access (#16). The limit: the disk is deleted with the cluster, so the data does not survive a rebuild (accepted for the demo).

**The four app components** (`k8s/app/auth.yaml`, `discounts.yaml`, `items.yaml`, `client.yaml`). Every pod is hardened the same way:

| Setting | What it stops |
| --- | --- |
| Runs as a non-root user | A break-out starts without root rights |
| No privilege escalation, all Linux capabilities dropped | The process cannot gain rights later |
| Read-only root filesystem (only `/tmp` writable where needed) | An attacker cannot drop tools or change files in the image |
| seccomp `RuntimeDefault` | Blocks rarely used, risky kernel calls |
| Own ServiceAccount, no Kubernetes API token mounted | A hacked pod has no key to the Kubernetes API |
| Memory limit | One pod cannot starve the node |
| 2 replicas, spread over nodes | One pod can restart while the other serves |

The `restauranty` namespace **enforces** these rules: Kubernetes' Pod Security "restricted" profile refuses any pod that breaks them, even one added by mistake later.

Images are pinned to the commit tag `bfb0e27`, not `latest`, so the cluster runs exactly the scanned image (entry 11).

**Secrets: one per workload, only what it needs.**

| Secret | Contents |
| --- | --- |
| `mongodb-secrets` | root password, app password |
| `auth-secrets` | app password, JWT **private** key (the only service that can sign tokens) |
| `discounts-secrets` | app password, JWT public key |
| `items-secrets` | app password, JWT public key, Cloudinary keys (needed to create items) |

For now the setup script copies the values from Key Vault into these Secrets. In #8, External Secrets takes over with one Azure identity per service, and keeps the same Secret names, so the Deployments do not change.

**The setup script** (`scripts/setup-aks.sh`) does everything in order and is safe to run again:

1. Checks that `kubectl` points at our cluster.
2. Installs the Gateway API CRDs, NGINX Gateway Fabric 2.8.1 and cert-manager v1.21.3 (exact versions).
3. Applies the namespaces, storage class, Gateway, issuers and certificate.
4. Creates the Secrets from Key Vault (values passed as files, never as command arguments).
5. Deploys MongoDB, waits for it, then deploys the app and the routes.
6. Prints the status.

```bash
./scripts/setup-aks.sh
kubectl get certificate -n gateway        # READY=True after a few minutes
curl -kI https://restauranty.aks.springlaughing.dev   # -k while the certificate is from staging
```

**Proof: the smoke test** (9 November, after `./scripts/setup-aks.sh`):

| Check | Command (short) | Result |
| --- | --- | --- |
| Static IP on the Gateway | `kubectl get gateway -n gateway` | `ADDRESS 4.182.101.186`, `PROGRAMMED True` |
| HTTP goes to HTTPS | `curl -I http://restauranty.aks.springlaughing.dev/menu` | `301`, `Location: https://.../menu` |
| Certificate | `openssl s_client ... \| openssl x509 -noout -issuer -ext subjectAltName` | Let's Encrypt (STAGING), both names; `READY True` after 90 seconds |
| Routing | `curl -k https://.../api/auth` (and the others) | Each backend answers "... Server UP!"; `/` gives the React page |
| `/metrics` not public | `curl -k https://.../metrics` | The React page: the backends' metrics are not reachable from outside |
| No token, no data | `curl -k https://.../api/items/items` | `401` |
| Sign up and log in | `POST /api/auth/signup`, `POST /api/auth/login` | `201`, then a token signed with `RS256` |
| Token accepted | items, coupons, `/api/auth/verify` with the token | `200` each |
| MongoDB users | MongoDB log on first start | `Created user 'restauranty' with readWrite on 'restauranty'` |

**One stop on the way.** The first run stopped with `line 119: f: command not found`. The script file had been edited while it was running. Bash reads a script from disk bit by bit, so it resumed in the middle of a changed line. Everything before that point was already applied. The second run finished, and showed that the script is safe to repeat: unchanged things stay `unchanged`. Lesson: never edit a script while it runs.

**Cloudinary is needed to create items.** Item images are uploaded to Cloudinary, and the create route always expects an image (`backend/items/routes/items.routes.js` reads `req.file.path` with no check). Without Cloudinary keys, `items` starts and can list items, but creating one fails. Cloudinary is a separate company, so it is its own trust boundary: only `items` gets its keys. They go into Key Vault without passing through the shell history:

```bash
for n in cloud-name cloud-api-key cloud-api-secret; do
  read -rsp "$n: " V; echo        # -s: what you type is not shown
  az keyvault secret set --vault-name kv-evgenia-restauranty -n "$n" --file <(printf %s "$V") --output none
done; unset V
./scripts/setup-aks.sh             # picks them up and restarts the pods
```

### What was created in Part 4

| Thing | Where | State |
| --- | --- | --- |
| Role: AcrPull for the kubelet on the registry | Azure, `terraform/cluster-access/` | Applied |
| Role: Network Contributor for the cluster on `rg-evgenia-restauranty` | Azure, `terraform/cluster-access/` | Applied |
| A records `restauranty`, `grafana` → `4.182.101.186` | Azure DNS, `terraform/persistent/dns.tf` | Applied |
| `mongo-password` replaced with hex | Key Vault | Done |
| `mongo-root-password` | Key Vault | Created by the script (first run) |
| Namespaces `gateway`, `restauranty` (Pod Security enforced) | `k8s/platform/namespaces.yaml` | Deployed |
| Storage class `managed-csi-zrs` | `k8s/platform/storageclass.yaml` | Deployed |
| Gateway + HTTP→HTTPS redirect | `k8s/platform/gateway.yaml` | Deployed |
| Let's Encrypt issuers (staging, production) + certificate | `k8s/platform/cluster-issuers.yaml`, `certificate.yaml` | Deployed |
| Helm values for NGINX Gateway Fabric and cert-manager | `k8s/platform/*-values.yaml` | Deployed |
| MongoDB StatefulSet with two users | `k8s/app/mongodb.yaml` | Deployed |
| auth, discounts, items, client + their ServiceAccounts and Services | `k8s/app/*.yaml` | Deployed |
| Path routing | `k8s/app/httproute.yaml` | Deployed |
| Setup script | `scripts/setup-aks.sh` | Used (safe to run again) |

---

## What is next

| Task | Issue |
| --- | --- |
| docker-compose for local dev | #1 |
| Cloudinary keys, then create an item; production certificate | #7 |
| Per-service identities, External Secrets, NetworkPolicies | #8, #11 |
| Gateway block on the user list, login rate limit | #10 |
| Pipeline with security gates | #12, #13 |
| Monitoring, alerts, the attack demo | #14, #15 |
