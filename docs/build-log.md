# Build log: Restauranty DevSecOps on AKS

**What this is.** A day-by-day record of what was built and why. Each entry has the goal, the commands, and the result, so the work can be followed or repeated later. It sits next to the [security assessment](security-assessment.md), which explains the problems; this log shows the fixes being built.

**How to read it.** Entries are in order. Each one starts with its result in one line. You can read any entry on its own.

**Three kinds of numbers.** They are unrelated to each other:

| Looks like | Means | Example |
| --- | --- | --- |
| `26.` at the start of a heading | An entry in this log. Entries count up through the whole log, from 1; they do not restart in each part. | 26. Before #10 |
| `#10` | An issue on GitHub: one piece of planned work | #10 = Gateway block and rate limit |
| `F6` | A finding in the [security assessment](security-assessment.md) | F6 = no limit on login attempts |

So "entry 11" (the Dockerfiles) and "issue #11" (the network rules) are different things. Headings without a number, such as "What is Trivy", explain an idea; numbered entries record work that was done.

**Parts 1 to 5 are from 9 November 2026, Part 6 from 10 November.**

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
- [Part 5 — secrets from Key Vault, one identity per service](#part-5--secrets-from-key-vault-one-identity-per-service)
  - [16. Before #8: one person copies every secret](#16-before-8-one-person-copies-every-secret)
  - [17. What #8 introduces](#17-what-8-introduces)
  - [18. Azure: one identity per workload](#18-azure-one-identity-per-workload)
  - [19. Kubernetes: External Secrets and Reloader](#19-kubernetes-external-secrets-and-reloader)
  - [What #8 creates](#what-8-creates)
- [Part 6 — network rules](#part-6--network-rules)
  - [20. Before #11: every pod can reach every pod](#20-before-11-every-pod-can-reach-every-pod)
  - [21. The rules: deny everything, then open what the app uses](#21-the-rules-deny-everything-then-open-what-the-app-uses)
  - [22. The test: assume a pod is already hacked](#22-the-test-assume-a-pod-is-already-hacked)
  - [23. Surprise: after a cluster restart, the backends lost MongoDB](#23-surprise-after-a-cluster-restart-the-backends-lost-mongodb)
  - [24. Before the rules: the attacker reaches MongoDB, the password holds](#24-before-the-rules-the-attacker-reaches-mongodb-the-password-holds)
  - [25. After the rules: every attack blocked, the app still works](#25-after-the-rules-every-attack-blocked-the-app-still-works)
  - [What #11 creates](#what-11-creates)
- [Part 7 — rules at the edge](#part-7--rules-at-the-edge)
  - [What "the edge" means](#what-the-edge-means)
  - [26. Before #10: what the code fixes left open](#26-before-10-what-the-code-fixes-left-open)
  - [27. The rules: close the user list, slow down guessing, stop floods](#27-the-rules-close-the-user-list-slow-down-guessing-stop-floods)
  - [Rate limiting: why, and how it works](#rate-limiting-why-and-how-it-works)
  - [28. Two surprises: a refused pattern and a test too slow to matter](#28-two-surprises-a-refused-pattern-and-a-test-too-slow-to-matter)
  - [29. After the rules: 11 of 11](#29-after-the-rules-11-of-11)
  - [What #10 creates](#what-10-creates)
- [Part 8 — the pipeline](#part-8--the-pipeline)
  - [What a pipeline is](#what-a-pipeline-is)
  - [How GitHub signs in to Azure: OIDC and federated identity](#how-github-signs-in-to-azure-oidc-and-federated-identity)
  - [What "azurerm" is](#what-azurerm-is)
  - [30. Azure: two identities, one to push, one to deploy](#30-azure-two-identities-one-to-push-one-to-deploy)
  - [How the pipeline reaches the cluster: the whole chain](#how-the-pipeline-reaches-the-cluster-the-whole-chain)
  - [31. GitHub: the approval gate and branch protection](#31-github-the-approval-gate-and-branch-protection)
  - [32. The workflow, part by part](#32-the-workflow-part-by-part)
  - [When the pipeline deploys, and how production teams do it](#when-the-pipeline-deploys-and-how-production-teams-do-it)
  - [33. First run: the pull request](#33-first-run-the-pull-request)
  - [34. First run on main: Entra ID refused the sign-in](#34-first-run-on-main-entra-id-refused-the-sign-in)
  - [35. First deploy by the pipeline](#35-first-deploy-by-the-pipeline)
  - [36. Proof: a run from a feature branch is refused](#36-proof-a-run-from-a-feature-branch-is-refused)
  - [What #12 creates](#what-12-creates)
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

**Files changed** (`backend/*` = in all three backends): `backend/*/config/jwt.js` (new: loads the key), `backend/*/middleware/jwt.middleware.js` (checks tokens with the public key), `backend/*/app.js`, `backend/*/.env.example`, `backend/auth/routes/auth.routes.js` (signs with the private key). Commit `d4ccc8f`.

**Proof:** a token forged with the old secret was accepted before, refused (401) after. Retest 1 in the assessment.

### 4. Code fix: 401 instead of 500, and brief errors

**Result:** a bad token gets "401 not allowed", not "500 server error". Bad input gets a short message, not the raw database error. (Fixes F8, F17.)

- Token errors: the shared error handler (`backend/*/error-handling/index.js`) answers 401 and writes one short log line, so attacks no longer look like server outages.
- Input errors: 32 route handlers used to send the whole database error (model and field names). They now pass the error on, and the handler answers `Invalid id` or `Invalid or missing fields`. The details go only to the log.

**Files changed:** `backend/*/error-handling/index.js` (the shared error handler), and the route files that sent raw errors: `backend/auth/routes/users.routes.js`, `backend/discounts/routes/campaigns.routes.js`, `coupons.routes.js`, `backend/items/routes/dietary.routes.js`, `items.routes.js`, `orders.routes.js`. Commits `1522185`, `6f93d8b`.

### 5. Code fix: one login answer

**Result:** login gives the same answer whether or not the email exists, so it no longer reveals which emails have an account. (Fixes F4.)

Before: an unknown email got "User not found." (fast), a wrong password got "Email or Password Incorrect" (slow). Now both get the same message, and an unknown email is still checked against a dummy hash so the response takes the same time.

**File changed:** `backend/auth/routes/auth.routes.js` (the login route). Commit `bbcb0be`.

### 6. Code fix: no password hashes, no personal data in logs

**Result:** no answer contains a password hash, and the logs no longer contain personal data. (Fixes F11, F14, F15, F3.)

- The User model hides the `password` field by default and strips it from every answer. Login is the only query that loads it.
- The `console.log` lines that wrote token content (email, address, phone) and whole records were removed.

**Files changed:** `backend/*/models/User.model.js` (the `password` field hidden), `backend/auth/routes/auth.routes.js` (login asks for the hash explicitly; log lines removed), `backend/items/routes/dietary.routes.js`, `orders.routes.js` (log lines removed). Commits `81efba4`, `6a17c02`.

PRs #22 covered entries 3 to 6. Each fix is one commit.

### 7. Code fix: a login token on every data route

**Result:** every data route in discounts and items now requires a valid token, and the frontend sends the token. (Fixes F12, F13; the brief's own task, #9.)

- The token check runs where the routes are mounted (`backend/*/app.js`), so a new route is protected automatically. Health checks, `/metrics`, signup and login stay public on purpose.
- The frontend adds the token to every call to our own API, through one axios interceptor (`client/src/services/apiToken.js`).

**Files changed:** `backend/*/app.js` (the token check where routes are mounted), `client/src/services/apiToken.js` (new: adds the token) and `client/src/index.jsx` (loads it). Commits `2773060`, `957ec48`.

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

**Result:** the app runs on AKS at https://restauranty.aks.springlaughing.dev, behind the static IP, with a trusted Let's Encrypt certificate (staging first, production the same evening). Sign-up, login, token checks and creating an item with an image all work end to end.

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

**The routes** (`k8s/app/httproute.yaml`) say which path goes to which service. The Gateway is the door; the routes are the signs behind it. One object of the kind **HTTPRoute** holds four rules:

| Path starts with | Goes to |
| --- | --- |
| `/api/auth` | auth |
| `/api/discounts` | discounts |
| `/api/items` | items |
| `/` (everything else) | client |

The longest matching path wins, so `/api/items/...` goes to items and not to the client. The backends' `/metrics` pages are not routed: a request for `/metrics` lands on the client, so the internet cannot read them.

**Why an HTTPRoute and not an Ingress.** The brief asks for an Ingress, the older Kubernetes object for the same job. **Gateway API** (Gateway + HTTPRoute) is its successor, with three advantages here:

- **Two owners, two files.** The Gateway (the door, HTTPS, the certificate) belongs to the platform; the routes belong to the app. With an Ingress, both are in one object.
- **Rules without vendor tricks.** Path rules, redirects and policies such as rate limits are part of the standard or attach to it cleanly. An Ingress needs controller-specific annotations for most of this.
- **The controller the brief names is retired.** The brief suggests the NGINX Ingress controller. The Kubernetes project retired it: maintenance ended in March 2026, so it gets no more security fixes. The project recommends moving to Gateway API ([Kubernetes blog, 11 Nov 2025](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). For a project about security, starting on software with no security fixes would be the wrong choice.

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
| Create an item with an image | `POST /api/items/items` as a form with a PNG, with the token | `200`; the item's image URL is on `res.cloudinary.com` and loads (`200 image/png`); without a token `401` |

**One stop on the way.** The first run stopped with `line 119: f: command not found`. The script file had been edited while it was running. Bash reads a script from disk bit by bit, so it resumed in the middle of a changed line. Everything before that point was already applied. The second run finished, and showed that the script is safe to repeat: unchanged things stay `unchanged`. Lesson: never edit a script while it runs.

**Switched to the production certificate the same evening.** The staging certificate cannot be used in a browser here: `.dev` is on the browsers' **HSTS preload list**, so every browser forces HTTPS for it and refuses an untrusted certificate with no "accept the risk" button. The browser said "Verbindung nicht sicher" and offered no way through. So `certificate.yaml` now uses `letsencrypt-prod`. The new certificate was ready in under a minute: issuer `Let's Encrypt YE1`, valid until 7 February 2027, and `curl` works without `-k`.

This is the same path as the vote app on AKS (staging first, then production). The difference is the plan to rebuild the cluster daily until the demo.

**Backup of the certificate, so rebuilds do not use up the limit.** Let's Encrypt allows 5 production certificates per week for the same names. A rebuilt cluster has no certificate, so cert-manager would request a new one every time. The setup script now:

1. saves the certificate Secret in Key Vault as `restauranty-tls-backup`, after it is ready, and again only when it changes (step 6);
2. after a rebuild, puts it back **before** the Certificate is applied (step 3). cert-manager finds a valid certificate with the right names and issuer, and requests nothing.

The backup keeps only what cert-manager checks: the certificate, the private key, and cert-manager's labels and annotations. An expired copy does no harm: cert-manager just renews it.

**Trade-off:** the private key now has a second home, in Key Vault. Only the operator can read it there (Secrets Officer role), it is encrypted, and every read is logged. If it ever leaks, the answer is the same as before: revoke the certificate and issue a new one.

**This backup is a workaround.** It solves a problem that exists only because the cluster is destroyed and rebuilt every day to save money. In a normal setup the cluster stays up, the certificate stays in it, and cert-manager renews it in place about every 60 days. Nothing needs a backup. Better options, and why they are not used this week:

| Option | How it works | Why not now |
| --- | --- | --- |
| Stop the cluster instead of destroying it (`az aks stop`, `az aks start`) | The nodes are switched off, so no compute cost, but everything stays: the certificate, MongoDB's data, the Secrets | A good fit, and it would also keep MongoDB's data. It is a change of habit from the vote app's destroy and rebuild, so it is left as a next step. |
| Key Vault as the home of the certificate | The certificate lives in Key Vault, and the cluster only gets a copy (Key Vault CSI driver or External Secrets, see #8) | The proper version of this backup. More setup than one script step. |
| HTTPS ends outside the cluster | Azure Application Gateway or Front Door holds the certificate; the cluster gets the traffic after it | Costs more, and replaces the Gateway built here |

**If the limit is hit anyway**, the site is down but the app keeps running: cert-manager's request is refused, the Certificate stays `READY False`, and the Gateway has no certificate to serve. Staging is no fallback, since browsers refuse it for `.dev`. The fastest way out is to change the set of names: the limit counts per exact set, so removing `grafana` from `certificate.yaml` (or adding a new name with its own DNS record) gives 5 fresh certificates within minutes. Otherwise, one slot comes back every 34 hours, or another free certificate authority (ZeroSSL, Google Trust Services) can be added as a second ClusterIssuer.

**Cloudinary is needed to create items.** Item images are uploaded to Cloudinary, and the create route always expects an image (`backend/items/routes/items.routes.js` reads `req.file.path` with no check). Without Cloudinary keys, `items` starts and can list items, but creating one fails. Cloudinary is a separate company, so it is its own trust boundary: only `items` gets its keys. They go into Key Vault without passing through the shell history:

```bash
for n in cloud-name cloud-api-key cloud-api-secret; do
  read -rsp "$n: " V; echo        # -s: what you type is not shown
  az keyvault secret set --vault-name kv-evgenia-restauranty -n "$n" --file <(printf %s "$V") --output none
done; unset V
./scripts/setup-aks.sh             # picks them up and restarts the pods
```

Done the same evening: a free Cloudinary account with its own API key named `restauranty`, so it can be deleted after the course without touching anything else. The cloud name is not a secret (it is part of every image URL); the API secret is.

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
| Let's Encrypt issuers (staging, production) + certificate (production since 9 Nov) | `k8s/platform/cluster-issuers.yaml`, `certificate.yaml` | Deployed |
| `cloud-name`, `cloud-api-key`, `cloud-api-secret` (own Cloudinary account and key) | Key Vault, set by hand with `read -s` | Done |
| `restauranty-tls-backup` (copy of the certificate Secret) | Key Vault, written by `scripts/setup-aks.sh` | Done |
| Helm settings for NGINX Gateway Fabric: no usage data sent to the vendor, raw NGINX snippets off, the Gateway's Service keeps the caller's real IP (`externalTrafficPolicy: Local`, needed for the rate limits in #10) | `k8s/platform/nginx-gateway-fabric-values.yaml` | Deployed |
| Helm settings for cert-manager: installs its object types, and may use Gateway API for the Let's Encrypt check (off by default) | `k8s/platform/cert-manager-values.yaml` | Deployed |
| MongoDB StatefulSet with two users | `k8s/app/mongodb.yaml` | Deployed |
| auth, discounts, items, client + their ServiceAccounts and Services | `k8s/app/*.yaml` | Deployed |
| Path routing | `k8s/app/httproute.yaml` | Deployed |
| Setup script | `scripts/setup-aks.sh` | Used (safe to run again) |

---

## Part 5 — secrets from Key Vault, one identity per service

Goal: every secret reaches the cluster through External Secrets, and each service signs in to Key Vault as its **own** Azure identity that can read only its own secrets. Issue #8, branch `8-external-secrets`.

### 16. Before #8: one person copies every secret

**In one line:** after #7, the secrets were copied into the cluster by the setup script, running as me.

**How it worked.** `scripts/setup-aks.sh` ran on my laptop, signed in to Azure as me. I have "Key Vault Secrets Officer" on the whole vault, so the script could read **every** secret. It read them all and wrote four Kubernetes Secrets, one per workload (`auth-secrets`, `discounts-secrets`, `items-secrets`, `mongodb-secrets`). Then it restarted all app pods, so they picked up the values.

```
Me (laptop, az login) ──reads ALL secrets──> Key Vault
        │
        └──kubectl create secret──> auth-secrets, discounts-secrets, items-secrets, mongodb-secrets
```

The split per workload was already right: `auth` was the only one with the private key, `items` the only one with the Cloudinary keys. But the split was only as good as the script.

**What was wrong with that:**

| Problem | Why it matters |
| --- | --- |
| One identity reads everything | The cluster had no Azure identity of its own. The separation between services existed only in my script, not in Azure. Nothing in Azure would stop a mistake in the script from giving `items` the private key. |
| Everything depends on my login | Every deployment needs a person with full read rights on the vault. A pipeline (#12) would need the same broad rights. |
| Changes do not arrive by themselves | A new value in Key Vault (for example a rotated password, #16) reaches the cluster only when someone runs the script again. |
| Restarts every time | The script restarted all app pods on every run, even when no value had changed. |

### 17. What #8 introduces

**In one line:** each workload gets its own Azure identity, and a controller in the cluster (External Secrets) fetches each workload's secrets **as that workload**.

```
                                   Entra ID
 ServiceAccount "items" ──token──>  "trust the cluster's token        ──Azure token──> Key Vault
   (in the cluster)                  for restauranty:items only"                       "items may read these
                                     (federated credential)                             5 secrets, nothing else"
        ▲                                                                                     │
        │ External Secrets does the sign-in on items' behalf                                 │
        └──────────────── writes Secret items-secrets <───────────────────────────────────────┘
                                   │
                                   └── Reloader restarts items, only if a value changed
```

| | Before #8 | After #8 |
| --- | --- | --- |
| Who reads Key Vault | Me, with rights on the whole vault | Each workload, as its own identity |
| What each one can read | Everything (only the script held back) | Only its own secrets: a role per single secret, enforced by Azure |
| Passwords to get in | My `az login` | None: the cluster's own signed token is exchanged for an Azure token (Workload Identity) |
| A changed value in Key Vault | Arrives when I run the script again | Arrives by itself within the hour (`refreshInterval: 1h`), or at once on request |
| Pod restarts | Every script run | Only when a value really changed (Reloader) |
| If Key Vault is down | Nothing changes until the next run | The last synced Secret stays; the app keeps running |

**The proof the issue asks for:** `items` asks Key Vault for `auth`'s private key and is refused. Before #8 that test was impossible, because there was only one identity (mine).

### 18. Azure: one identity per workload

**Result:** applied (`Apply complete! Resources: 19 added, 0 changed, 0 destroyed`). Lives in `terraform/cluster-access/workload-identity.tf`. The role assignments took up to 30 seconds each: Azure checks every new role before it confirms it.

Three kinds of Azure resources, per workload (`auth`, `discounts`, `items`, `mongodb`):

| Resource | What it is | Count |
| --- | --- | --- |
| Managed identity `id-evgenia-restauranty-<name>` | The workload's Azure account. No password exists for it. | 4 |
| Federated credential | The rule "accept the cluster's token for `system:serviceaccount:restauranty:<name>`". Any other ServiceAccount, namespace or cluster is refused. | 4 |
| Role "Key Vault Secrets User" on **one secret** | Read that one secret's value. Not list, not change, not delete, and not any other secret. | 11 |

**Who may read what** (`variable "workload_secrets"`):

| Workload | Secrets |
| --- | --- |
| `auth` | `jwt-private-key`, `mongo-password` |
| `discounts` | `jwt-public-key`, `mongo-password` |
| `items` | `jwt-public-key`, `mongo-password`, `cloud-name`, `cloud-api-key`, `cloud-api-secret` |
| `mongodb` | `mongo-root-password`, `mongo-password` |

**Why the identities live in the persistent resource group.** Their client ids are written into the ServiceAccounts, so they should not change. A rebuilt cluster gets a new OIDC issuer (the address that signs its tokens), so on the next `terraform apply` only the 4 federated credentials are replaced. The identities and their roles stay.

**Why no secret ever lands in Terraform state.** The role scope is written as a plain string, `<vault id>/secrets/<name>`. Terraform's `azurerm_key_vault_secret` data source would have been easier, but it copies the secret's **value** into the state file.

```bash
cd terraform/cluster-access
terraform plan -out access.tfplan   # review: 19 to add
terraform apply access.tfplan
terraform output workload_client_ids   # 4 client ids, for the ServiceAccounts
```

### 19. Kubernetes: External Secrets and Reloader

**Result:** deployed. All four ExternalSecrets synced on the first try, each signed in as its own identity. The hand-over from the old Secrets restarted no pod.

**Two new tools**, installed by the setup script with Helm:

| Tool | Job | Locked down how |
| --- | --- | --- |
| External Secrets Operator 2.14.0 | Fetches secrets from Key Vault and writes them as Kubernetes Secrets | Cluster-wide stores switched off: a `ClusterSecretStore` would let any namespace read through one shared identity. Writing back to Key Vault (`PushSecret`) switched off. |
| Reloader 2.2.18 | Restarts a Deployment when its Secret changes | Only Deployments that ask for it; only the `restauranty` namespace (a Role there, no cluster-wide rights) |

**Per workload, three objects** (in each workload's own file, e.g. `k8s/app/auth.yaml`):

1. **ServiceAccount** with the annotation `azure.workload.identity/client-id`: "I stand for this Azure identity". The client id is not a secret: without the federated credential it opens nothing.
2. **SecretStore**: "Key Vault, signed in as this ServiceAccount". One per workload, so no workload can use another one's sign-in.
3. **ExternalSecret**: "fill the Secret `auth-secrets` with these keys". Same Secret names as before, so the Deployments' environment variables do not change.

The three backends get the annotation `secret.reloader.stakater.com/reload: "<name>-secrets"`. MongoDB does not: it reads its passwords only on its very first start, so a restart would only cause downtime. Changing a MongoDB password is done inside MongoDB (#16).

**What changes in `scripts/setup-aks.sh`:**

| Before | After |
| --- | --- |
| Reads every secret and creates the four Secrets | Installs External Secrets and Reloader, then only checks that the secrets exist in Key Vault |
| `kubectl rollout restart` on every run | No restart: Reloader handles it |
| — | Waits until every ExternalSecret reports `Ready` |
| — | One-time hand-over: deletes the four Secrets made by the old script, so External Secrets can create its own. Running pods keep their values; nothing restarts. |

**Two things to know:**

- **External Secrets is now a very trusted component.** Its controller may read and write every Secret in the cluster, including the HTTPS key in `gateway`. That is how it works, and cert-manager is the same. Both go into the threat model (#3).
- **Not everything moves to External Secrets.** The HTTPS certificate backup (entry 15) still goes through the script, because it writes **to** Key Vault, and no workload identity is allowed to write.

**Proof 1: the hand-over.** After `./scripts/setup-aks.sh`:

| Check | Result |
| --- | --- |
| `kubectl get externalsecret -n restauranty` | `auth-secrets`, `discounts-secrets`, `items-secrets`, `mongodb-secrets`: all `SecretSynced`, `READY True` |
| Who owns each Secret | `ExternalSecret/<name>`; each holds exactly its own keys (e.g. `auth-secrets`: `jwt-private-key`, `mongo-password`) |
| Did a pod restart? | No: the ReplicaSets were still the ones from before #8 (54-64 minutes old) |
| App | Sign-up `201`; items and coupons with a token `200` |

**Proof 2: `items` cannot read `auth`'s secret.** The test is a file, so it can be replayed in the demo: `k8s/proof/items-asks-for-auth-secret.yaml`. It is an ExternalSecret that uses **items'** SecretStore and asks for `jwt-private-key`.

```bash
kubectl apply -f k8s/proof/items-asks-for-auth-secret.yaml
kubectl get externalsecret proof-items-asks-for-private-key -n restauranty   # SecretSyncedError, READY False
kubectl logs -n external-secrets deploy/external-secrets | grep proof-items   # Key Vault's answer
kubectl delete -f k8s/proof/items-asks-for-auth-secret.yaml
```

Key Vault's answer, shortened:

```
Status=403 Code="Forbidden"  InnerError={"code":"ForbiddenByRbac"}
Caller: appid=c4cca0e5-8a35-4900-b62a-c0f6ff45bcbe        <- items' identity
Action: 'Microsoft.KeyVault/vaults/secrets/getSecret/action'
Resource: .../vaults/kv-evgenia-restauranty/secrets/jwt-private-key
Assignment: (not found)
```

Azure itself refuses, not a script: the caller is `items`' identity, and it has no role on that secret. No Secret was created in the cluster. Before #8 this test was not possible, because only one identity (mine) read Key Vault.

### What #8 creates

| Thing | Where | State |
| --- | --- | --- |
| 4 managed identities, 4 federated credentials, 11 single-secret roles | Azure, `terraform/cluster-access/workload-identity.tf` | Applied |
| External Secrets and Reloader settings | `k8s/platform/external-secrets-values.yaml`, `reloader-values.yaml` | Deployed |
| ServiceAccount annotation, SecretStore, ExternalSecret per workload | `k8s/app/auth.yaml`, `discounts.yaml`, `items.yaml`, `mongodb.yaml` | Deployed |
| Reloader annotation on auth, discounts, items | the same files | Deployed |
| Setup script: install both tools, no more copying or restarting | `scripts/setup-aks.sh` | Used |
| Proof: `items` refused when it asks for `auth`'s secret | `k8s/proof/items-asks-for-auth-secret.yaml` | Done: `403 ForbiddenByRbac` |

---

## Part 6 — network rules

Goal: a pod that is taken over can reach only what its job needs. Nothing else in the cluster can reach the database or the services except through the Gateway. Issue #11, branch `11-network-policies`.

The cluster was stopped overnight with `az aks stop` and started again with `az aks start`. Everything came back as it was: pods, MongoDB's disk, the certificate, the secrets.

### 20. Before #11: every pod can reach every pod

**In one line:** by default, Kubernetes lets any pod open a connection to any other pod, in any namespace.

That is a Kubernetes design choice, not a mistake in this cluster. It means "inside the cluster" protects nothing on its own:

| From | To | Allowed before #11? |
| --- | --- | --- |
| Any pod in any namespace | MongoDB, port 27017 | Yes |
| Any pod | `auth`, `discounts`, `items` directly, around the Gateway | Yes |
| `discounts` | `auth` (they never talk to each other) | Yes |
| `auth` | Any address on the internet | Yes |
| Any pod | The Azure metadata service, 169.254.169.254 | Yes |

The rules to change this are called **NetworkPolicies**. Kubernetes only stores them: a separate component, the policy engine, must enforce them. Without one, the rules are accepted and silently ignored. This cluster has one: Cilium, switched on in entry 8.

### 21. The rules: deny everything, then open what the app uses

**In one line:** five rules in `k8s/network/policies.yaml`. The first blocks everything; the other four open only the paths the app really uses.

**The paths the app really uses**, found by reading the code: the backends never call each other, and only `items` calls the internet (Cloudinary).

```
internet ──> Gateway ──> client, auth, discounts, items   (each on its port "http")
                         auth, discounts, items ──> MongoDB :27017
                         auth, discounts, items ──> cluster DNS :53
                         items ──> Cloudinary, HTTPS :443
```

| Rule | What it allows |
| --- | --- |
| `default-deny` | Nothing, in or out, for every pod in `restauranty` |
| `from-gateway` | The Gateway's NGINX pods reach the four app components on their `http` port |
| `mongodb-from-backends` | Only `auth`, `discounts` and `items` reach MongoDB, on 27017 |
| `backends-to-mongodb-and-dns` | The three backends may call MongoDB and the cluster DNS |
| `items-to-internet-https` | `items` may call HTTPS on public addresses, for Cloudinary |

**How the Gateway is recognised.** By its namespace (`gateway`) **and** a label on its pods. Checked on the cluster before applying the rules:

```
$ kubectl get pods -n gateway --show-labels
NAME                                 READY   STATUS    RESTARTS   AGE   LABELS
restauranty-nginx-85c5954cc8-6x6bh   1/1     Running   0          14h   app.kubernetes.io/instance=nginx-gateway,...,gateway.networking.k8s.io/gateway-name=restauranty,...
```

**What the rules cannot do:**

- **Name a website.** A NetworkPolicy knows IP addresses, not names. So `items` may reach **any** public HTTPS address, not just `api.cloudinary.com`. Allowing a single domain needs Cilium's FQDN rules, which on AKS come with the paid Advanced Container Networking Services. Known gap.
- **Stop an admin.** Someone with rights to create pods can usually delete the rules too. NetworkPolicies protect against a **taken-over app**, not a taken-over admin; that is the job of Kubernetes RBAC.

**Not in this step:** the monitoring paths (Prometheus reads `/metrics`, logs go to Loki). The monitoring namespace does not exist yet; its rules come with #14.

The setup script applies the rules after the app is up (`kubectl apply -f k8s/network/`), so a rebuilt cluster gets them too.

### 22. The test: assume a pod is already hacked

**In one line:** the test does not show how an attacker gets in. It assumes they already did, and checks what they can reach. Security people call this **assume breach**.

Real attackers get into a pod through a bug in a library (Log4Shell, 2021), a poisoned npm package (event-stream, 2018), or stolen deploy rights (Tesla's open Kubernetes dashboard, 2018). The network rules do not stop the break-in. They limit what happens after it.

**Two kinds of attacker** (`k8s/proof/attacker-pods.yaml` and the app pods themselves):

| Attacker | Stands for |
| --- | --- |
| Pod `attacker` in `restauranty`: just `curl`, no `app` label | A new container the attacker controls, right next to the app |
| Pod `attacker` in `default` | The same, somewhere else in the cluster |
| The real `auth`, `discounts`, `items` pods (`kubectl exec`) | A bug in the app's code: the attacker runs code inside a real app pod |

**The test script** `scripts/test-network.sh` runs 15 checks and prints PASS or FAIL for each:

- **The app still works:** the website loads, a wrong login gets `401` (auth must ask MongoDB to say so), and `items` reaches Cloudinary.
- **The attackers are blocked:** both attacker pods try MongoDB and `auth`.
- **A hacked app pod is boxed in:** `discounts` tries `auth`, `auth` tries the internet, and `items` tries the Azure metadata service. That last address is how the Capital One breach (2019) got its cloud credentials.
- **No app ServiceAccount may read Secrets:** `kubectl auth can-i` for all five.

The targets are **pod IP addresses, not names**. A pod without a DNS rule cannot look up a name, so the test would then show a DNS failure instead of a blocked connection. "Blocked" means the connection attempt timed out: the packet was dropped on the way and never arrived.

**Prediction, written before the first run:**

| Group | Checks | Without rules | With rules |
| --- | --- | --- | --- |
| The app still works | 3 | PASS | PASS |
| Attacker in `restauranty` | 2 | FAIL: gets through | PASS: blocked |
| Attacker in `default` | 2 | FAIL: gets through | PASS: blocked |
| Hacked app pod | 3 | FAIL: gets through | PASS: blocked |
| ServiceAccounts and Secrets | 5 | PASS (no rights since #8) | PASS |
| **Total** | 15 | **8 passed, 7 failed** | **15 passed** |

### 23. Surprise: after a cluster restart, the backends lost MongoDB

**In one line:** the first run gave one result that was not predicted. Its cause was not the network: after `az aks start`, the three backends had lost MongoDB for good, while Kubernetes showed every pod as healthy.

**The first run**, with the attacker pods in place and no rules yet:

```
$ kubectl apply -f k8s/proof/attacker-pods.yaml
pod/attacker created
pod/attacker created

$ ./scripts/test-network.sh
Policies in restauranty: 0

The app still works
  PASS  internet -> Gateway -> client                           200
  FAIL  internet -> Gateway -> auth -> MongoDB (wrong login)    expected 401, got 500
  PASS  items -> Cloudinary (api.cloudinary.com:443)            open

A hacked pod in the app namespace
  FAIL  attacker -> MongoDB :27017                              expected blocked, got open
  FAIL  attacker -> auth :3001                                  expected blocked, got open

A hacked pod in another namespace
  FAIL  attacker (default) -> MongoDB :27017                    expected blocked, got open
  FAIL  attacker (default) -> auth :3001                        expected blocked, got open

A hacked app pod
  FAIL  discounts -> auth :3001 (backends do not call each other) expected blocked, got open
  FAIL  auth -> internet (1.1.1.1:443, no way to send data out) expected blocked, got open
  FAIL  items -> Azure metadata service (169.254.169.254:80)    expected blocked, got open

No app ServiceAccount may read Secrets
  PASS  ServiceAccount auth: get secrets                        no
  PASS  ServiceAccount discounts: get secrets                   no
  PASS  ServiceAccount items: get secrets                       no
  PASS  ServiceAccount client: get secrets                      no
  PASS  ServiceAccount mongodb: get secrets                     no

7 passed, 8 failed
```

Every attack got through, as predicted. But the wrong login answered `500` instead of `401`, and with no rules in place, nothing could be blocking it.

**Step 1: the same request by hand.**

```
$ curl -s -w '\nHTTP %{http_code}\n' -X POST https://restauranty.aks.springlaughing.dev/api/auth/login \
    -H 'Content-Type: application/json' -d '{"email":"nobody@example.com","password":"wrong"}'
{"message":"Internal server error"}
HTTP 500
```

**Step 2: auth's log.** Auth waits 10 seconds for the database, then gives up:

```
$ kubectl logs -n restauranty -l app=auth --since=10m
Error updating user count: MongooseError: Operation `users.countDocuments()` buffering timed out after 10000ms
```

**Step 3: every backend's log, from its start.** All six backend pods failed to find MongoDB by name:

```
$ kubectl logs -n restauranty <each auth, discounts, items pod> | grep -i mongo
Error connecting to mongo:  MongoNetworkError: getaddrinfo ENOTFOUND mongodb
```

**Step 4: when each pod started.** All at the same moment, MongoDB included:

```
$ kubectl get pods -n restauranty -o custom-columns=NAME:.metadata.name,STARTED:.status.containerStatuses[0].state.running.startedAt
auth-5b7d75d54-kkj72         2026-11-10T12:35:29Z
items-5ddb9fb88d-thn9f       2026-11-10T12:35:28Z
discounts-6bcf5f64d4-5mmbj   2026-11-10T12:35:47Z
mongodb-0                    2026-11-10T12:35:53Z
...
```

**Step 5: the name works now.**

```
$ kubectl exec -n restauranty deploy/auth -- node -e 'require("dns").lookup("mongodb",(e,a)=>console.log(e?e.code:a))'
192.168.0.114
```

**What happened.**

1. `az aks start` started all pods at once. Some backends were up **before** MongoDB.
2. The name `mongodb` belongs to a headless Service. Kubernetes publishes such a name only once its pod is ready. So for those first seconds the name did not exist: `ENOTFOUND`.
3. The backends try to connect **once**, at start. On failure, `backend/*/db/index.js` only logs the error and never tries again.
4. A few seconds later MongoDB was ready and the name worked, but no backend asked again.
5. The health checks only ask "does the web server answer?", not "can you reach the database?". So every pod stayed `Running` and `Ready`, while every login failed.

**Why it matters.** This is an outage that nothing reported: Kubernetes saw healthy pods, and the only sign was users getting errors. The app already measures it: `mongo_connection_status` was 0 in all three backends. An alert on that metric (#14, #15) would have caught it.

**Fixed for now** by restarting the backends, so they connect again:

```bash
kubectl rollout restart deployment auth discounts items -n restauranty
```

**The real fix** is in the code, so a restart is never needed: when the first connection fails, the app exits, and Kubernetes starts it again until MongoDB is there. It has its own issue, [#28](https://github.com/springlaughing/restauranty-devsecops-aks/issues/28), so the network change stays separate.

### 24. Before the rules: the attacker reaches MongoDB, the password holds

**In one line:** with no rules, the attacker pod reaches MongoDB over the network. It cannot log in: MongoDB's password is a second, separate wall.

**Attack 1: knock on the door.** The attacker pod has only `curl`, which speaks HTTP:

```
$ MONGO=$(kubectl get pod mongodb-0 -n restauranty -o jsonpath='{.status.podIP}')
$ kubectl exec -n restauranty attacker -- curl -s --max-time 5 http://$MONGO:27017
It looks like you are trying to access MongoDB over HTTP on the native driver port.
```

What happened, step by step:

1. `curl` opened a network connection to MongoDB's port 27017. Nothing stopped it.
2. It sent an HTTP request, but MongoDB does not speak HTTP; it has its own protocol.
3. MongoDB recognised the HTTP text and answered with that fixed sentence. This happens **before any login**: it is the database saying "wrong language", not "welcome".

Like knocking on a door and hearing "wrong door!" from inside: the attacker now knows the door exists and someone is behind it, but has not opened it. No password was used and no data was read. The MongoDB password never left the backends' Secrets, and the attacker pod cannot read Secrets (entry 22: all five `can-i` checks say `no`).

**Attack 2: try a real database command.** A second attacker, this time with MongoDB's own client, from the `default` namespace:

```
$ kubectl run mongo-attacker -n default --rm -it --restart=Never --image=mongo:8.0.34 -- \
    mongosh --host $MONGO --quiet --eval 'db.adminCommand({listDatabases: 1})'
MongoServerError: Command listDatabases requires authentication
pod "mongo-attacker" deleted from default namespace
```

The request **reached** MongoDB, and MongoDB refused it. The password is the only wall still standing.

**Why reaching it matters, even with a password:**

| What the attacker can do with the door in reach | Why |
| --- | --- |
| Guess passwords | From inside the cluster, no Gateway rate limit applies |
| Use a bug that works before login | **MongoBleed** (CVE-2025-14847, December 2025): anyone who could connect could read pieces of the server's memory, no password needed. Exploited in real attacks; fixed in 8.0.17. This cluster runs `mongo:8.0.34`, so it is safe from this one, but the next such bug will hit someone unpatched. |
| Learn about the server | A bare connection already reveals facts that help choose an exploit |

**Two walls, two jobs.** Network rules decide who may **knock**; authentication decides who may **enter**. Before #11 only the second wall existed. After #11 both must fail before anyone reaches the data. That is defence in depth.

### 25. After the rules: every attack blocked, the app still works

**In one line:** 15 of 15 checks pass. Every attack from entry 22 times out, and the app's own paths still work.

**One variable at a time.** First the backends were restarted (entry 23) and the login checked **without** rules: `401`. So if the login broke after the rules, the rules would be the only possible cause.

```
$ kubectl rollout restart deployment auth discounts items -n restauranty
$ curl -s -o /dev/null -w '%{http_code}\n' -X POST https://restauranty.aks.springlaughing.dev/api/auth/login \
    -H 'Content-Type: application/json' -d '{"email":"nobody@example.com","password":"wrong"}'
401

$ kubectl apply -f k8s/network/policies.yaml
networkpolicy.networking.k8s.io/default-deny created
networkpolicy.networking.k8s.io/from-gateway created
networkpolicy.networking.k8s.io/mongodb-from-backends created
networkpolicy.networking.k8s.io/backends-to-mongodb-and-dns created
networkpolicy.networking.k8s.io/items-to-internet-https created
```

**Before and after, side by side** (full outputs: `docs/evidence/11-network-before.txt`, `11-network-after.txt`):

| Check | Before (0 rules) | After (5 rules) |
| --- | --- | --- |
| internet → Gateway → client | 200 | 200 |
| internet → Gateway → auth → MongoDB (wrong login) | 500 (entry 23, not the network) | 401 |
| items → Cloudinary | open | open |
| attacker → MongoDB | **open** | blocked |
| attacker → auth | **open** | blocked |
| attacker (default) → MongoDB | **open** | blocked |
| attacker (default) → auth | **open** | blocked |
| discounts → auth | **open** | blocked |
| auth → internet | **open** | blocked |
| items → Azure metadata service | **open** | blocked |
| 5 ServiceAccounts: get secrets | no | no |
| **Result** | 7 passed, 8 failed | **15 passed, 0 failed** |

```
$ ./scripts/test-network.sh
Policies in restauranty: 5

The app still works
  PASS  internet -> Gateway -> client                           200
  PASS  internet -> Gateway -> auth -> MongoDB (wrong login)    401
  PASS  items -> Cloudinary (api.cloudinary.com:443)            open

A hacked pod in the app namespace
  PASS  attacker -> MongoDB :27017                              blocked
  PASS  attacker -> auth :3001                                  blocked

A hacked pod in another namespace
  PASS  attacker (default) -> MongoDB :27017                    blocked
  PASS  attacker (default) -> auth :3001                        blocked

A hacked app pod
  PASS  discounts -> auth :3001 (backends do not call each other) blocked
  PASS  auth -> internet (1.1.1.1:443, no way to send data out) blocked
  PASS  items -> Azure metadata service (169.254.169.254:80)    blocked

No app ServiceAccount may read Secrets
  PASS  ServiceAccount auth: get secrets                        no
  PASS  ServiceAccount discounts: get secrets                   no
  PASS  ServiceAccount items: get secrets                       no
  PASS  ServiceAccount client: get secrets                      no
  PASS  ServiceAccount mongodb: get secrets                     no

15 passed, 0 failed
```

**The two MongoDB attacks from entry 24, again:**

```
$ kubectl exec -n restauranty attacker -- curl -s --max-time 5 http://$MONGO:27017; echo " (exit $?)"
command terminated with exit code 28
 (exit 28)

$ kubectl run mongo-attacker -n default --rm -it --restart=Never --image=mongo:8.0.34 -- \
    mongosh --host $MONGO --quiet --eval 'db.adminCommand({listDatabases: 1})'
MongoServerSelectionError: Socket 'connect' timed out after 30004ms (connectTimeoutMS: 30000)
```

| | Before | After |
| --- | --- | --- |
| `curl` | MongoDB answers: "It looks like you are trying to access MongoDB over HTTP..." | Exit 28: timed out, no answer |
| `mongosh` | `requires authentication`: MongoDB got the command and refused it | `Socket 'connect' timed out`: MongoDB never saw anything |

The error changes **kind**, not just text. "requires authentication" comes from MongoDB: the server received the request. A timeout comes from nowhere: the packet was dropped on the way. The attacker can no longer even knock.

**The one path to the internet still works.** The test above only proves `items` can open a connection to Cloudinary. The real proof is an upload: an item created with an image in the browser, with the rules on.

```
$ kubectl logs -n restauranty -l app=items -f --since=1m | grep -v 'GET /api/items '
POST /api/items/dietary 200 77.803 ms - 169
GET /api/items/items 200 7.110 ms - 350
POST /api/items/items 200 1135.593 ms - 250
```

The item was saved with `200`. It took about one second, while the other requests took milliseconds: that second is `items` uploading the file to Cloudinary before it answers. The image address is `https://res.cloudinary.com/.../restaurant/...jpg`.

Showing the image is a different path: the browser loads it straight from Cloudinary, never through the cluster. So the `200` on the POST is the proof, not the picture on screen.

**A false alarm on the first "after" run.** The first run gave 14 of 15: `attacker (default) -> auth :3001` reported "open". The same check against both running auth pods, by hand, timed out (exit 28). The cause was the test script, not the rules:

1. The restart had just replaced the auth pods; the old one was still shutting down.
2. The script took the first auth pod in the list, which could be the old one. A pod that is shutting down is no longer protected by the rules, so it most likely answered "connection refused".
3. The script counted everything except a timeout as "open".

From the other attacker the same address still showed "blocked": that attacker's own outbound rule (default deny) drops the packet before it leaves. The `default` attacker has no outbound rules, so its packet reached the dying pod.

**Fixed in the script:** it now picks only running pods that are not shutting down, and reports anything other than "connected" or "timed out" as `error (exit N)`, never as "open" or "blocked". The second run: 15 of 15.

### What #11 creates

| Thing | Where | State |
| --- | --- | --- |
| 5 NetworkPolicies: default deny, then Gateway in, backends to MongoDB and DNS, `items` to HTTPS | `k8s/network/policies.yaml` | Applied |
| Two attacker pods (`restauranty`, `default`) | `k8s/proof/attacker-pods.yaml` | Used for the test |
| Test with 15 checks, PASS/FAIL | `scripts/test-network.sh` | 15 of 15 |
| Item with image, rules on | Browser + `items` log | `POST /api/items/items 200`, image on Cloudinary |
| Setup script applies the rules after the app | `scripts/setup-aks.sh` | Ready for the next rebuild |
| Before/after outputs | `docs/evidence/11-network-before.txt`, `11-network-after.txt` | Saved |
| New issue: backends never reconnect to MongoDB | [#28](https://github.com/springlaughing/restauranty-devsecops-aks/issues/28) | Open |

---

## Part 7 — rules at the edge

**Goal:** stop three kinds of harmful requests at the Gateway, before they reach any service. The Gateway is the app's front door: every request from the internet passes through it first.

| Harmful request | What the Gateway answers |
| --- | --- |
| Anyone asks for the list of all users (`/api/auth/users`) | `403 Forbidden`, always, for everyone |
| One address tries many logins in a row (password guessing) | After 6 tries: `429 Too Many Requests` |
| One address sends a huge number of requests (a flood) | Above 50 a second: `429 Too Many Requests` |

**Why at the Gateway, when the code is already fixed?** The code now checks the login token and never sends password hashes. But code changes. If a later change breaks the token check by mistake, the Gateway still refuses these requests. Two separate checks are harder to get past than one.

**Its place in the project.** The [approach](approach.md) follows a real incident in four steps: contain, close, guard, detect. This part is **contain**: block the attack at the front door first, fast, without touching the code. The code fixes (Part 1) were **close**: the real repair inside the app.

Issue #10, branch `10-gateway-block-rate-limit`.

### What "the edge" means

**In one line:** the edge is the border between the internet and my system: the first thing of mine that a request from outside touches. Here, that is the Gateway.

![Restauranty on AKS with four trust boundaries](images/trust-boundary.png)

**How to read the picture.** Each red dashed line is a **trust boundary**: a place where a request moves from a side I trust less to a side I trust more, so it must be checked there.

| Line | Between | Checked there by |
| --- | --- | --- |
| TB1 | The internet and the Gateway | The Gateway: HTTPS, routing, the rules in this part |
| TB2 | The Gateway and the four services | The services: the login token check (#9); the network rules (#11) |
| TB3 | The services and MongoDB | The network rules (#11) and MongoDB's password |
| TB4 | The cluster and Azure (Key Vault, Entra ID) or Cloudinary | One Azure identity per service (#8) |

**The edge is TB1**, the top red line: the first place where a request from the internet meets something of mine. Everything in this part happens there, in the blue Gateway box. Some boxes are still to come: GitHub Actions (#12) and Monitoring (#14, #15).

The word comes from networking: an "edge router" sits at the edge of a company network, and content networks (CDNs) have "edge locations" close to users. It always means the outer border, where outside traffic first arrives.

**Why put rules at the edge:**

| Reason | What it means here |
| --- | --- |
| Earliest point | A refused request costs one line of NGINX work. It never starts Node.js, never runs bcrypt, never touches MongoDB. |
| One place for all services | One flood limit covers client, auth, discounts, items and, later, Grafana. No service needs its own copy. |
| No code change | The rules work even for code I cannot or do not want to change, for example a third-party app. |
| Fast to deploy | A Gateway rule is live seconds after `kubectl apply`. A code fix needs a build, a scan and a rollout. That is why "contain" comes before "close" in an incident. |

**What the edge cannot do.** The Gateway sees the request: address, path, headers, how often. It does not know the user, the account or the business rules. So it cannot say "this user may see only their own orders". That stays in the code. So the edge is only the **first** check a request meets, never the only one. Several independent checks, one behind the other, are called **defence in depth**: if one fails, the next still holds.

**Why the test is called the edge test.** `scripts/test-edge.sh` runs from my laptop, **outside** the cluster, exactly like a stranger on the internet. Every request crosses the edge. Compare with the network test of #11:

| Test | Runs from | Tests |
| --- | --- | --- |
| `scripts/test-edge.sh` (#10) | Outside: my laptop, over the internet | What a stranger can do through the front door |
| `scripts/test-network.sh` (#11) | Inside: pods in the cluster | What a hacked pod can do once it is already in |

Together they cover both directions: the front door, and the rooms behind it.

### 26. Before #10: what the code fixes left open

**In one line:** the code fixes made the worst leak smaller, but did not close it. And nothing slowed down password guessing.

**F-numbers** (F1 to F20) are the findings in the [security assessment](security-assessment.md), the test of the app as I received it.

**The user list (findings F11, F14, F15).** On day one, `/api/auth/users` gave every user's password hash to anyone, without login. The code fixes changed that: a token is needed (#9), and no answer contains a hash (#21). What is left:

- Any logged-in user still gets every user's email, address and phone number.
- Anyone can sign up, and every new user is admin (finding F1).
- The frontend never calls this route. Nobody needs it from the internet.
- Capital letters reach it too: Express, the web framework inside auth, ignores case, so `/api/auth/USERS` runs the same code as `/api/auth/users`. So a Gateway rule that closes this path must cover every spelling (entry 27).

**Password guessing (finding F6).** About 10 guesses per second, with no limit and no slowdown.

**Floods.** No limit at all: one machine could send as many requests as it likes.

**The test** `scripts/test-edge.sh` runs from my laptop, like a stranger on the internet, in four groups:

- **The app still works:** the website, auth, the items API and a wrong login.
- **The user list is closed:** five ways of writing its path.
- **Password guessing is limited:** 20 wrong logins in a row.
- **A flood is refused:** 300 requests at once.

**403 or 401 shows who answered.** 401 comes from the app's token check; 403 comes from the Gateway. So the test proves which layer stopped the request.

```
$ ./scripts/test-edge.sh
Edge rules: 0 policies

The app still works
  PASS  GET /  (the website)                             200
  PASS  GET /api/auth  (auth is up)                      200
  PASS  GET /api/items/items, no token  (reaches the app) 401
  PASS  POST /api/auth/login, wrong password             401

The user list is closed at the Gateway (403 = Gateway, 401 = the app)
  FAIL  GET /api/auth/users                              expected 403, got 401
  FAIL  GET /api/auth/USERS                              expected 403, got 401
  FAIL  GET /api/auth/Users                              expected 403, got 401
  FAIL  GET /api/auth/users/                             expected 403, got 401
  FAIL  GET /api/auth/users/000000000000000000000000     expected 403, got 401

Password guessing: 20 wrong logins in a row
        answers: 20 x 401, 0 x 429
  FAIL  some guesses refused with 429                    expected yes, got no

Flood: 300 requests at once from one address
        answers: 300 x 200, 0 x 429
  FAIL  some requests refused with 429                   expected yes, got no

4 passed, 7 failed
```

As predicted: every request reaches the app, every guess gets an answer, every flood request is served.

### 27. The rules: close the user list, slow down guessing, stop floods

**In one line:** three rules at the Gateway, in two **new** files. No existing file was changed: the normal routes in `k8s/app/httproute.yaml` stay as they were.

| File | New or changed | What it holds |
| --- | --- | --- |
| `k8s/app/edge-rules.yaml` | New | The user list block, and the login route with its limit |
| `k8s/platform/rate-limit.yaml` | New | The flood limit for the whole Gateway |
| `scripts/setup-aks.sh` | One line added | Applies `rate-limit.yaml` after a rebuild. `edge-rules.yaml` needs no line: the script already applies every file in `k8s/app/`. |

**How new routes win over old ones without editing them.** The Gateway collects all routes for the same address and, for each request, picks the most specific match. `/api/auth/users` and `/api/auth/login` (new file) are more specific than `/api/auth` (old file), so they win. Every other request still follows the old routes.

| Rule | What it does | Kind |
| --- | --- | --- |
| `block-user-list` | Every path starting with `/api/auth/users`, in any mix of upper and lower case, answers **403**. The request never reaches auth. | HTTPRoute + AccessPolicy "deny everyone" |
| `login` | 10 logins per minute per IP address, with room for 5 quick tries first. More answer **429** (Too Many Requests). | HTTPRoute + RateLimitPolicy |
| `flood` | 50 requests per second per IP address on everything, with room for a burst of 100. More answer **429**. | RateLimitPolicy on the Gateway |

**Blocking the user list: every spelling, not only lowercase.**

The user list is closed by a rule at the Gateway, a **block**: the Gateway answers `403 Forbidden` itself, and the request never reaches auth. The block does not match only the exact path `/api/auth/users`. It also matches every mix of upper and lower case: `USERS`, `Users`, and so on. The reason is how the two programs read letters:

- The **Gateway** compares letters exactly: `u` is not `U`.
- **Express**, the web framework inside auth, ignores case: `USERS` runs the same user list code as `users`.

So a block for lowercase `users` only would let `/api/auth/USERS` through to the user list.

The block is in `k8s/app/edge-rules.yaml`. Two parts:

```yaml
# Part 1: a route that matches the user list path, in any case.
# [Uu] means "u or U", and so on for each letter.
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: block-user-list
  namespace: restauranty
spec:
  parentRefs:
    - name: restauranty
      namespace: gateway
      sectionName: https-app
  hostnames:
    - restauranty.aks.springlaughing.dev
  rules:
    - matches:
        - path: { type: RegularExpression, value: "/api/auth/[Uu][Ss][Ee][Rr][Ss]" }
      backendRefs:
        - { name: auth, port: 80 }   # required by the format; no request gets here
---
# Part 2: refuse every caller on that route. The Gateway answers 403 itself.
apiVersion: gateway.nginx.org/v1alpha1
kind: AccessPolicy
metadata:
  name: block-user-list
  namespace: restauranty
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: block-user-list
  action: Deny
  rules:
    - name: everyone-ipv4
      source:
        type: IPAddress
        ipAddress: { address: 0.0.0.0/0 }   # every IPv4 address
    - name: everyone-ipv6
      source:
        type: IPAddress
        ipAddress: { address: "::/0" }      # every IPv6 address
```

**The user routes: closed at the Gateway, kept in the code.** auth has four user routes: list all users, get one, change one, delete one. The block is only a Gateway rule; the code in `backend/auth/routes/users.routes.js` is unchanged. Why not delete the routes?

| Question | Answer |
| --- | --- |
| Are the routes needed? | Yes, in a real restaurant: an admin must be able to manage users. The frontend does not use them yet. |
| What would the proper fix be? | A role check in auth: only real admins may call these routes (authorization by role, often called RBAC). |
| Why not this week? | Every new user is admin (finding F1). A role check that everyone passes protects nothing. Fixing it means changing sign-up, creating the first admin, and adding the check: real app work. |
| So what now? | **Contain:** the Gateway closes the routes for everyone. The proper fix goes into SECURITY.md as "production would add" (#19). |
| Can an admin still reach them? | Only someone with rights on the cluster, with `kubectl port-forward` straight to auth, around the Gateway. An emergency door for the few people who are trusted anyway. |

**Why each rule is its own route.** A policy applies to a whole HTTPRoute. So the user list and login get their own small routes, and more specific paths win over the general `/api/auth` route.

**Why 403 and not 500.** The simplest way to block a path is a route with nowhere to send it. But then the Gateway answers `500 Internal Server Error`, which means "something broke". In the assessment, the app made the same mistake (finding F8): attacks were answered with 500, so in the logs they looked like server faults, not attacks. Instead, the rule says "deny everyone": every IPv4 address (`0.0.0.0/0`) and every IPv6 address (`::/0`). Then NGINX answers `403 Forbidden`, which means "refused on purpose".

**How much slower guessing gets.** Before: about 10 guesses per second, so 36,000 an hour. After: 10 a minute, so 600 an hour, 60 times fewer. A person who mistypes a password twice never notices the limit.

**How much traffic is normal.** Loading the app is about 10 requests; a person clicking around sends a few per second. The flood limit is far above both. It stops one machine from overloading the app, but not a flood from many machines at once (a DDoS). That needs Azure DDoS Protection or a firewall in front: out of scope.

**Why the limits can count per person.** The key is the caller's IP address. The Gateway's Service keeps the real client IP (`externalTrafficPolicy: Local`, entry 15). Without it, NGINX would see the node's address, and every visitor would share one count.

```
$ kubectl apply -f k8s/app/edge-rules.yaml -f k8s/platform/rate-limit.yaml
httproute.gateway.networking.k8s.io/block-user-list created
accesspolicy.gateway.nginx.org/block-user-list created
httproute.gateway.networking.k8s.io/login created
ratelimitpolicy.gateway.nginx.org/login created
ratelimitpolicy.gateway.nginx.org/flood created
```

The setup script applies both files, so a rebuilt cluster gets the rules too.

### Rate limiting: why, and how it works

**In one line:** a rate limit caps how many requests one caller may send in a given time. Above the cap, the Gateway answers `429 Too Many Requests` instead of passing the request on.

#### Why: three attacks that need speed

Many attacks only work because a computer can try very fast. A rate limit does not make them impossible; it makes them too slow to pay off.

| Attack | How it works | Why speed matters |
| --- | --- | --- |
| **Brute force** | Many passwords against one account | Needs thousands of tries for one weak password |
| **Password spraying** | One common password (`Password1`) against many accounts | Needs one try per account, across all accounts |
| **Credential stuffing** | Email and password pairs leaked from **other** sites, tried here | People reuse passwords. Leaked lists have millions of pairs; each pair is one try |
| **Flooding** | As many requests as possible, to slow down or stop the app | Without a cap, one machine can keep every service busy |

**A real case: 23andMe, 2023.** Attackers used credential stuffing: logins leaked from other sites, tried on 23andMe. About 14,000 accounts opened, roughly 0.1% of users. Through a feature that shows relatives' profiles, those accounts gave access to data of about 6.9 million people. The company said its own systems were not broken into: the attackers simply logged in, many times, with passwords that worked.

**In this app (finding F6):** about 10 guesses per second, no limit, no slowdown. And the weak passwords from F5 (`Password1`, `Qwerty123`) were accepted. Together that is the brute-force and spraying case exactly.

**A second reason: logins are expensive.**

- Every login checks the password with **bcrypt**. bcrypt is slow on purpose, so that stolen password hashes take very long to crack.
- auth runs on Node.js, which handles all requests on **one thread**: one line of work at a time.
- The login code uses `bcrypt.compareSync`. "Sync" means auth does nothing else until the check is done. While it checks one password, every other user waits.
- A login with an unknown email does the same work, on purpose: then the answer time does not reveal which emails exist (finding F4).

So a stream of logins does more than guess passwords: it keeps auth busy, and real users wait. The limit protects auth's CPU too.



#### How: the code, and what it does

The login limit is in `k8s/app/edge-rules.yaml`:

```yaml
apiVersion: gateway.nginx.org/v1alpha1
kind: RateLimitPolicy
metadata:
  name: login
  namespace: restauranty
spec:
  targetRefs:                   # which route the limit is for
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: login               # the route for /api/auth/login only
  rateLimit:
    rejectCode: 429             # the answer when a caller is over the limit
    logLevel: warn
    local:
      rules:
        - key: $binary_remote_addr   # count per caller IP address
          rate: 10r/m                # 10 requests per minute
          burst: 5                   # plus 5 extra, right away
          noDelay: true              # serve the 5 extra at once, do not hold them back
```

What each line means:

| Line | In plain words |
| --- | --- |
| `key: $binary_remote_addr` | Each IP address is counted on its own. Two callers never share a count. |
| `rate: 10r/m` | 10 logins per minute. NGINX spreads this evenly: **one login every 6 seconds**, not 10 at once and then nothing. |
| `burst: 5` | On top of that, up to **5 extra** logins are allowed right away. A person who mistypes a password twice never notices the limit. |
| `noDelay: true` | The 5 extra are answered at once. Without it, NGINX would hold them and answer one every 6 seconds, so the login would feel slow. |
| `rejectCode: 429` | When a caller has used all of that up, the Gateway answers `429 Too Many Requests` itself. auth never sees the request. |

The flood limit in `k8s/platform/rate-limit.yaml` has the same lines, with `rate: 50r/s` (50 per second, so one every 20 milliseconds) and `burst: 100`. It applies to every path, not only login.

**Why 429 and not 403.** 403 means "never allowed". 429 means "allowed, but not this fast: wait". A normal program that gets 429 knows to slow down and try again later. The user list gets 403 because it is closed for good.

#### The test, and why the numbers come out as they do

The test sends logins as fast as it can, from one address. This is the code in `scripts/test-edge.sh`:

```bash
# Before this group, "the app still works" already sent 1 wrong login.
codes=$(for i in $(seq 20); do wrong_login; echo; done)    # 20 wrong logins in a row
```

The result, from the "after" run:

```
Password guessing: 20 wrong logins in a row
        answers: 5 x 401, 15 x 429
```

Counting all wrong logins in this run, one after the other, within a fraction of a second:

| Login number | Allowed by | Answer |
| --- | --- | --- |
| 1 (in "the app still works") | the normal rate | `401`: auth checked the password |
| 2 to 6 (first 5 in the loop) | the 5 extra (`burst: 5`) | `401` |
| 7 to 21 (the other 15) | nothing left | `429`: the Gateway refused |

So 6 logins reached auth, then everything was refused. After 6 seconds, one more login would be allowed, then one every 6 seconds.

**The flood test** sends 300 requests for the home page, 50 at a time:

```bash
codes=$(curl -s -Z --parallel-max 50 --max-time 15 -w '%{stderr}%{http_code}\n' "$URL/?n=[1-300]" 2>&1 >/dev/null)
```

```
Flood: 300 requests at once from one address
        answers: 119 x 200, 181 x 429
```

The 300 requests took about 0.45 seconds. In that time the limit allows: 1 at the normal rate, plus 100 extra (`burst: 100`), plus about 22 more (50 per second for 0.45 seconds). That is about 123; the test got 119. The small difference comes from timing. The rest, 181, got `429`.

#### Proof: the Gateway counts each caller by their real address

The limits only work if NGINX sees the caller's real public address. If it saw an address from inside Azure instead, every visitor would share one count. The Gateway's own log, after the test:

```
$ kubectl logs -n gateway <gateway pod> | grep -a 'api/auth/login' | tail -1
<my IP> - - [10/Nov/2026:17:47:14 +0000] "POST /api/auth/login HTTP/2.0" 429 162 "-" "curl/7.81.0"

$ kubectl logs -n gateway <gateway pod> | grep -a 'limiting requests' | tail -2
[warn] limiting requests, excess: 5.020 by zone "restauranty_rl_login_rule0", client: <my IP>, ...
[warn] limiting requests, excess: 100.200 by zone "gateway_rl_flood_rule0", client: <my IP>, request: "GET /?n=300 ...
```

(`grep -a` reads the log as text: it contains a few non-text bytes, and without `-a` grep prints nothing.)

| Part of the line | Meaning |
| --- | --- |
| `<my IP>`, `client: <my IP>` | My laptop's real public address. NGINX counts per real caller. |
| `zone "restauranty_rl_login_rule0"` | The login limit's own count. The flood limit has a separate one, `gateway_rl_flood_rule0`. |
| `excess: 5.020` | Just over the 5 extra logins allowed (`burst: 5`): refused |
| `excess: 100.200` | Just over the 100 extra requests allowed (`burst: 100`): refused |

The same log shows other addresses from the internet. Each has its own count, so my test never slowed them down. **Many users at once are fine: the limits stop only one address that sends too much.** The exception is many people behind one shared address, in the table below.

#### Where to limit: at the edge or in the code

| | At the edge (this project) | In the code (for example `express-rate-limit`) |
| --- | --- | --- |
| Covers | Every service at once | One service |
| Cost of a refused request | Almost none: NGINX answers | Node.js already started on it |
| Knows the user or account | No, only the IP address | Yes: it could lock **one account** after 5 wrong passwords, from any address |
| Needs a code change | No | Yes |

The edge limit is the first check: cheap, and the same for every service. A per-account lock (5 wrong passwords, then the account waits) would be the next one, in the code. Not this week: it can also be abused to lock real users out, so it needs care.

#### What a rate limit per IP address does not stop

| Gap | Why | The answer |
| --- | --- | --- |
| **Many addresses** | A botnet has thousands of IP addresses, each with its own fresh bucket | Alert on many failed logins in total, from any address (#15) |
| **IPv6** | One home connection often gets billions of IPv6 addresses (a range written as `/64`); each address could get its own bucket | Count per `/64` range instead of per address. This Gateway is IPv4 only today |
| **Shared addresses** | An office or a mobile network puts many people behind one IP; they share one bucket | Fine for login (10 a minute); real traffic would need tuning, ideally from measurements |
| **More Gateway pods** | `local` limits count per NGINX pod. With 3 pods, a caller gets about 3 times the limit | One pod today. With more, lower the rate, or use a shared counter |
| **Floods from many machines** | A DDoS sends from thousands of machines at once | Azure DDoS Protection or a firewall in front of the Gateway: out of scope |

**How limits are set in real life.** Start with `dryRun: true`: NGINX counts and logs what it **would** refuse, but refuses nothing. Watch the logs for a week, see what normal users really send, then set the limit above that and switch dry run off. Here the limits come from estimates, not measurements: a known shortcut for a one-week project.

### 28. Two surprises: a refused pattern and a test too slow to matter

**In one line:** two things went wrong on the way. One rule was accepted by Kubernetes but did nothing. And one test sent its requests too slowly, so it never reached the limit and showed no effect.

**Surprise 1: the Gateway software refused the pattern, and only the route's status said so.**

The Gateway runs on **NGINX Gateway Fabric (NGF)**: software that reads the route files and turns them into NGINX settings. There are two checks when a route file is applied:

1. **Kubernetes** checks the file's format: are the fields there, is the path text? It said "created".
2. **NGF** checks whether it can turn the route into NGINX settings. It writes its answer into the route's **status**, a section Kubernetes adds to every object. `kubectl apply` does not show it.

The first version matched the path with the pattern `(?i)^/api/auth/users`. `(?i)` means "ignore upper and lower case". Kubernetes accepted it: it is valid text. NGF refused it, and said so only in the status:

```
$ kubectl get httproute block-user-list -n restauranty \
    -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
ResolvedRefs=True ResolvedRefs: All references are resolved
Accepted=False UnsupportedValue: All rules are invalid: spec.rules[0].matches[0].path.value:
  Invalid value: "(?i)^/api/auth/users": must start with / ...

$ curl -s -o /dev/null -w '%{http_code}\n' https://restauranty.aks.springlaughing.dev/api/auth/users
401        <- still reaches the app: the block does nothing
```

The fix: write both cases for each letter, `/api/auth/[Uu][Ss][Ee][Rr][Ss]`. That needs no flag and works in every pattern language. After that:

```
Accepted=True Accepted
Programmed=True Programmed: Policy is programmed in the data plane
/api/auth/users 403
/api/auth/USERS 403
```

**Lesson:** a Gateway rule can be "created" and still do nothing. Only its status (`status.conditions`) says whether NGF accepted it. Check it after every change.

**Surprise 2: the flood test was slower than the limit.** The first "after" run gave 10 of 11: the flood test got `300 x 200`, no 429. So I checked the NGINX config that NGF generated, inside the Gateway pod:

```
$ kubectl exec -n gateway <gateway pod> -- nginx -T | grep -nE 'limit_req|server_name|location'
594: limit_req_zone $binary_remote_addr zone=gateway_rl_flood_rule0:10m rate=50r/s;
279:     server_name restauranty.aks.springlaughing.dev;
280:     include .../RateLimitPolicy_gateway_flood_gateway_server.conf;   <- limit_req ... burst=100 nodelay
283:     location ~ ^/api/auth/[Uu][Ss][Ee][Rr][Ss] {
306:     location = /api/auth/login {
461:     location / {
```

The rule was there and in the right place. So the question was whether the test really sent more than 50 requests per second:

```
old way (300 curl processes, 50 at a time):
    300 200
  took 6.505140383 s                  <- about 46 requests/s: under the limit

one curl, 300 requests over shared connections, 50 at a time:
    112 200
    188 429
  took .445680269 s                   <- about 670 requests/s
```

Each separate `curl` starts a new process and does its own HTTPS handshake. Fifty of them in parallel from a laptop reached only about 46 requests per second, just under the limit. The rule was right; the test was too weak. The script now sends the flood from one `curl` that reuses its connections. The "before" result still stands: with no limit, a faster flood is also served in full.

Two more things the config showed:

- **NGF adds `^` to every pattern itself.** In a pattern, `^` means "the path must start here". The config shows `location ~ ^/api/auth/...` with a `^` my rule does not have. So `/other/api/auth/users` is not blocked by mistake, and that is why NGF wants patterns to start with `/`.
- **The login limit replaces the flood limit on `/api/auth/login`.** In NGINX, a location with its own `limit_req` does not inherit the server's. That is fine here, because the login limit is the stricter one.

### 29. After the rules: 11 of 11

**In one line:** the user list answers 403 in every spelling, password guessing gets 429 after 6 tries, and a flood gets 429 after about 120 requests. The app works as before.

```
$ ./scripts/test-edge.sh
Edge rules: 3 policies

The app still works
  PASS  GET /  (the website)                             200
  PASS  GET /api/auth  (auth is up)                      200
  PASS  GET /api/items/items, no token  (reaches the app) 401
  PASS  POST /api/auth/login, wrong password             401

The user list is closed at the Gateway (403 = Gateway, 401 = the app)
  PASS  GET /api/auth/users                              403
  PASS  GET /api/auth/USERS                              403
  PASS  GET /api/auth/Users                              403
  PASS  GET /api/auth/users/                             403
  PASS  GET /api/auth/users/000000000000000000000000     403

Password guessing: 20 wrong logins in a row
        answers: 5 x 401, 15 x 429
  PASS  some guesses refused with 429                    yes

Flood: 300 requests at once from one address
        answers: 119 x 200, 181 x 429
  PASS  some requests refused with 429                   yes

11 passed, 0 failed
```

| Check | Before | After |
| --- | --- | --- |
| The app (4 checks) | works | works |
| `/api/auth/users`, 5 spellings | 401: reaches the app | **403: refused at the Gateway** |
| 20 wrong logins | 20 answered | 6 answered (1 + burst of 5), then **429** |
| 300 requests at once | 300 served | about 120 served (burst of 100 + refill), then **429** |
| **Result** | 4 passed, 7 failed | **11 passed, 0 failed** |

Full outputs: `docs/evidence/10-edge-before.txt`, `10-edge-after.txt`.

**The day-one leak, now met three ways:** the Gateway refuses the route (#10), the code asks for a token (#9), and the code sends no hashes (#21). An alert on it comes with #15.

**What the rules do not stop:**

- **Guessing from many addresses.** The limits count per IP address; an attacker with many addresses (a botnet) gets a fresh count on each. The alert on many failed logins (#15) is the answer to that.
- **Users behind one shared address.** People in one office share an IP and one count. For the login limit that is acceptable (10 a minute); for real traffic it would need tuning.
- **A flood from many machines.** See entry 27: that needs protection in front of the Gateway.

### What #10 creates

| Thing | Where | State |
| --- | --- | --- |
| User list closed at the Gateway, any case, 403 | `k8s/app/edge-rules.yaml` (HTTPRoute + AccessPolicy) | Applied |
| Login limit: 10 a minute per IP, burst 5, 429 | `k8s/app/edge-rules.yaml` (HTTPRoute + RateLimitPolicy) | Applied |
| Flood limit: 50 a second per IP, burst 100, 429 | `k8s/platform/rate-limit.yaml` | Applied |
| Setup script applies the flood limit | `scripts/setup-aks.sh` | Ready for the next rebuild |
| Test with 11 checks, PASS/FAIL | `scripts/test-edge.sh` | 11 of 11 |
| Before/after outputs | `docs/evidence/10-edge-before.txt`, `10-edge-after.txt` | Saved |

---

## Part 8 — the pipeline

**Goal:** every change reaches the cluster the same way: built, tested and deployed by GitHub Actions, never from my laptop. GitHub gets into Azure without any password stored in GitHub. Issue #12, branch `12-pipeline`.

| When | What the pipeline does |
| --- | --- |
| Someone opens a pull request to `main` | Installs, tests and builds the four images. It does not sign in to Azure and pushes nothing. |
| A pull request is merged into `main` | The same, then pushes the four images to the registry, each tagged with the commit's ID |
| After the push | The deploy waits until I approve it in GitHub, then puts exactly those images on AKS and checks that the site answers |

### What a pipeline is

**In one line:** a pipeline is a list of steps that a service runs by itself on every change: build, test, deliver.

| Word | Meaning |
| --- | --- |
| **CI**, continuous integration | Every change is built and tested automatically, so a broken change shows up before it is merged |
| **CD**, continuous delivery | Tested changes are delivered to the servers automatically. "Delivery" when a person approves the last step; "deployment" when nobody does. This pipeline is delivery: I approve. |
| **GitHub Actions** | GitHub's own pipeline service |
| **Workflow** | One pipeline, written as a YAML file in `.github/workflows/`. Here: `.github/workflows/ci-cd.yaml`, the name the brief asks for |
| **Job** | A group of steps. Each job runs on its own fresh virtual machine from GitHub, called a **runner**, which is thrown away afterwards |
| **Step** | One command, or one ready-made **action** (a small published program, such as `actions/checkout`) |

**Before #12**, images were built and pushed from my laptop (entry 11), and the manifests were applied from my laptop (`scripts/setup-aks.sh`). That has three problems: it depends on my machine and on me remembering every step; nothing guarantees the tests ran; and my laptop needs the rights to change everything.

### How GitHub signs in to Azure: OIDC and federated identity

**In one line:** for each job, GitHub writes a short signed note that says who the job is. Azure checks the note against a rule I set up, and only then lets the job in. No password exists anywhere.

**The old way, and why it is risky.** Create a password for the pipeline in Azure (a "client secret") and store it in GitHub's secret settings. That password:

- lives for months or years;
- works from anywhere, for anyone who gets hold of it: a log that prints it by mistake, a poisoned package in the build, a break-in at the CI company;
- must be changed by hand.

**A real case: CircleCI, January 2023.** Malware on one CircleCI engineer's laptop stole a logged-in session. Through it, attackers reached CircleCI's systems, where customers' stored secrets were kept. CircleCI told every customer to rotate every secret stored with them: cloud keys, tokens, SSH keys. With OIDC there is nothing stored that could be stolen this way.

**The words of the new way:**

| Word | Meaning |
| --- | --- |
| **Entra ID** | Microsoft's identity service. It decides who may sign in to Azure. (Its old name is Azure Active Directory.) |
| **Managed identity** | An Azure account for a program, not a person. It has no password at all. "User-assigned" means I create it myself, as its own resource. |
| **OIDC**, OpenID Connect | A standard way for one service to prove an identity to another with a signed token |
| **OIDC token** | A short note GitHub writes and signs for one job, valid for minutes. It says, for example, "this job runs in repo springlaughing/restauranty-devsecops-aks, on branch main". Only GitHub can sign it, so nobody can fake it. |
| **Issuer** | Who signed the token: `https://token.actions.githubusercontent.com` |
| **Subject** | Who the token is about: the repo, plus the branch or the environment of the job |
| **Audience** | Who the token is meant for: `api://AzureADTokenExchange`, Entra ID's token exchange |
| **Federated credential** | A rule attached to a managed identity: "accept a token from this issuer, about exactly this subject, for this audience". "Federated" means Azure trusts another identity system (GitHub) for this one question. |

**What happens when a job signs in:**

```
 1. job ──"I need a token"──> GitHub                     (needs permission id-token: write)
 2. GitHub ──signed token──> job                         issuer   = token.actions.githubusercontent.com
                                                         subject  = repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:environment:production
                                                         audience = api://AzureADTokenExchange
 3. job ──token + "I want to be identity f4f5b9dd-…"──> Entra ID
 4. Entra ID checks: signed by GitHub? Issuer, subject and audience equal to a federated
    credential on that identity?
 5. yes ──> Azure access token for that identity, valid about one hour
    no  ──> refused
```

| | Client secret in GitHub | OIDC with a federated credential |
| --- | --- | --- |
| What is stored in GitHub | A password | Nothing secret. Only ids, which open nothing on their own |
| How long a stolen credential works | Until someone changes it, often months | The GitHub token: minutes. The Azure token: about an hour |
| Who can use it | Anyone, from anywhere | Only a job whose repo and branch or environment match the rule |
| Rotation | By hand | Nothing to rotate |

### What "azurerm" is

**Terraform** describes infrastructure in files, then creates it. Terraform itself knows no cloud. A **provider** is a plugin that turns Terraform files into one platform's API calls.

**azurerm** is the provider for Azure. The name comes from **Azure Resource Manager**, Azure's own layer that creates, changes and deletes every Azure resource. Every resource type that starts with `azurerm_`, such as `azurerm_user_assigned_identity`, comes from this provider. This project uses version 4.81.0, fixed in each layer's `.terraform.lock.hcl`, so every run uses the same version.

### 30. Azure: two identities, one to push, one to deploy

**In one line:** two managed identities with different rights, each trusted for a different kind of GitHub job. The powerful one is used only after I approve.

| Identity | May do in Azure | Trusted for jobs with subject | When it is used |
| --- | --- | --- | --- |
| `id-evgenia-restauranty-pipeline` (existed since entry 10) | Push images to the registry (role AcrPush) | `repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:ref:refs/heads/main`: the `main` branch | Every merge, automatically |
| `id-evgenia-restauranty-deploy` (new) | Fetch this one cluster's credentials (role "Azure Kubernetes Service Cluster User Role") | `repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:environment:production` | Only after I approve the deploy |

**Why two and not one.** The build job runs `npm ci`, which installs packages from the internet: 156 per backend, 1,516 for the client. Any of them could be poisoned (event-stream, 2018). If the build job had the deploy identity, a poisoned package could reach the cluster directly: read Secrets, delete things, change the network rules, without anyone approving. With two identities, the deploy identity exists only inside the approved deploy job.

**Where the two identities are defined.** Four places, three in Terraform and one in the workflow:

| What | File |
| --- | --- |
| Push identity `id-evgenia-restauranty-pipeline` and its role AcrPush | `terraform/persistent/main.tf` (made in entry 10; code below) |
| Deploy identity `id-evgenia-restauranty-deploy`, and the GitHub rules for both identities | `terraform/persistent/github.tf` (code further down in this entry) |
| Deploy identity's role on the cluster | `terraform/cluster-access/pipeline.tf` (code further down in this entry) |
| Which job signs in as which identity | `.github/workflows/ci-cd.yaml` (entry 32) |

The push identity, in `terraform/persistent/main.tf`:

```hcl
# The pipeline's Azure account. No password exists for it.
resource "azurerm_user_assigned_identity" "pipeline" {
  name                = "id-${local.name_suffix}-pipeline"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  tags                = local.common_tags
}

# Its only right: push and pull images in this one registry.
resource "azurerm_role_assignment" "pipeline_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
}
```

| Part | Meaning |
| --- | --- |
| `azurerm_user_assigned_identity` | Creates the identity: an Azure account for a program |
| `azurerm_role_assignment` | Gives it a right. Three parts: **who** (`principal_id`, the identity), **what** (`role_definition_name`, AcrPush), **where** (`scope`, the registry only) |

The deploy identity is built the same way: `azurerm_user_assigned_identity.deploy` in `github.tf`, and its one role in `cluster-access/pipeline.tf`, with the cluster as the scope.

**Each identity has exactly one role**, read back from Azure:

```
$ az role assignment list --assignee <principal id> --all --query "[].{role:roleDefinitionName, scope:scope}" -o tsv
== id-evgenia-restauranty-pipeline
AcrPush                                       .../registries/acrevgeniarestauranty
== id-evgenia-restauranty-deploy
Azure Kubernetes Service Cluster User Role    .../managedClusters/aks-evgenia-k8s-dev
```

**Why one can reach the cluster's Secrets and the other cannot.** The Secrets here are the Kubernetes Secrets inside the cluster (`auth-secrets` holds the JWT private key and the MongoDB password, `items-secrets` the Cloudinary keys). The only way to read them is the cluster's API, which needs two doors:

| Door | Pipeline identity (build job) | Deploy identity (deploy job) |
| --- | --- | --- |
| 1. Azure hands out the cluster's connection file (`az aks get-credentials`) only to an identity with a role on the cluster | Refused: it has no role on the cluster, so it cannot even talk to Kubernetes | Allowed: Cluster User Role |
| 2. Kubernetes checks the certificate in that file | Never gets here | Allowed: on this cluster it is the admin certificate (the known gap), so it could read every Secret |

Neither identity can read **Key Vault**, where the secrets are kept. Only the four workload identities (entry 18), each for its own secrets, and my own account can. The deploy job's only path to secret values is the copies that External Secrets writes into the cluster.

**What the split does not stop: a poisoned image.** The build job can still push an image, and an image is exactly what goes to production after my approval. A poisoned package gets into it in two ways:

| Way | What happens |
| --- | --- |
| The poison is in a package version | The package is inside the image like any other. The backends' final images keep every package the app needs to run (about 128 of 156; only the 28 development tools are left out). The client's final image has no `node_modules`, but the code of the libraries it uses is compiled into the JavaScript that every visitor's browser runs. |
| The poison runs during `npm ci` | Packages may have **install scripts**, which run while installing, with the job's rights. On `main`, the build job may ask for an OIDC token, so a script could sign in as the push identity and push any image, even replace the image under this commit's tag. Today three packages have install scripts (`fsevents`, macOS only; `core-js` and `core-js-pure`, which print a message), all harmless, but a new version could add one. |

**What protects already:** every package in the four lock files has an integrity hash (156 of 156, 1,516 of 1,516). `npm ci` refuses a package whose content does not match its hash. So a package cannot change silently under the same version: poison can only come in through a change to `package-lock.json`, which shows up in a pull request.

**Planned in #13:** `npm ci --ignore-scripts`, so install scripts never run; the build job split in two, so the job that runs npm code holds no identity and a separate job only pushes; deploy by digest (`image@sha256:…`) instead of tag, so the cluster runs exactly the image that was built and scanned; Trivy and `npm audit` for known bad versions. Image signing with a check in the cluster would be the production answer.

**New file `terraform/persistent/github.tf`:**

```hcl
locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]
}

# Build and push: every merge to main, no approval needed.
resource "azurerm_federated_identity_credential" "pipeline_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.pipeline.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = "${var.github_subject_prefix}:ref:refs/heads/main"
}

# Deploy: a separate identity. Its only right is on the cluster.
resource "azurerm_user_assigned_identity" "deploy" {
  name                = "id-${local.name_suffix}-deploy"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  tags                = local.common_tags
}

# Trusted only for jobs in the GitHub environment "production".
resource "azurerm_federated_identity_credential" "deploy_production" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = "${var.github_subject_prefix}:environment:production"
}
```

| Part | What it does |
| --- | --- |
| `locals` | Two values used twice below: GitHub's token signer, and Entra's token exchange as the audience |
| `pipeline_main` | The rule on the existing push identity: accept a GitHub token only for the `main` branch of this repo |
| `azurerm_user_assigned_identity.deploy` | The new deploy identity, in the persistent resource group, next to the push identity |
| `deploy_production` | The rule on the deploy identity: accept a GitHub token only for jobs in the environment `production` |
| `${var.github_subject_prefix}` | `repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318`: the start of the subject GitHub sends for this repo, from a new variable. The numbers are the ids of my GitHub account and of the repo (entry 34 explains why they are there). |

**New file `terraform/cluster-access/pipeline.tf`:**

```hcl
data "azurerm_user_assigned_identity" "deploy" {
  name                = "id-evgenia-restauranty-deploy"
  resource_group_name = data.azurerm_resource_group.persistent.name
}

# Allows "az aks get-credentials" for this cluster only.
resource "azurerm_role_assignment" "deploy_cluster_user" {
  scope                            = data.azurerm_kubernetes_cluster.aks.id
  role_definition_name             = "Azure Kubernetes Service Cluster User Role"
  principal_id                     = data.azurerm_user_assigned_identity.deploy.principal_id
  skip_service_principal_aad_check = true
}
```

| Part | What it does |
| --- | --- |
| `data "azurerm_user_assigned_identity"` | Looks up the deploy identity made by the persistent layer. A `data` block only reads; it never creates or deletes. |
| `scope = …aks.id` | The role applies to this one cluster, nothing else in Azure |
| `Azure Kubernetes Service Cluster User Role` | May ask Azure for the cluster's connection details (`az aks get-credentials`) |
| `skip_service_principal_aad_check` | The identity is brand new; this skips a check that can fail while Entra ID is still spreading it to all its servers |

**Why the files are in two different layers.** The identities and the GitHub rules go in `persistent`, which is never destroyed: GitHub's address never changes. The role goes in `cluster-access`, because it points at the cluster, and a rebuilt cluster gets a new id.

**Changes to existing files:**

| File | Change |
| --- | --- |
| `terraform/persistent/variables.tf` | New variable `github_subject_prefix` = `repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318` (first `github_repo` with names only; changed in entry 34) |
| `terraform/persistent/outputs.tf` | New output `deploy_client_id`, the id the workflow needs |
| `terraform/persistent/main.tf` | Comment only: the push identity's GitHub rule is now in `github.tf` |

**A renamed field.** The first plan warned that `resource_group_name` and then `parent_id` are "deprecated" (old, to be removed). The installed provider's own description shows the new name:

```
$ terraform providers schema -json | jq -r '.provider_schemas[].resource_schemas.azurerm_federated_identity_credential.block.attributes | to_entries[] | "\(.key) deprecated=\(.value.deprecated // false)"'
parent_id  deprecated=true
resource_group_name  deprecated=true
user_assigned_identity_id  deprecated=false
...
```

So the rules use `user_assigned_identity_id`. Asking the installed provider is safer than a web page, which may describe another version.

**Applied, in this order** (the second layer looks up the identity the first one creates):

```
$ cd terraform/persistent && terraform apply persistent.tfplan
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
deploy_client_id = "f4f5b9dd-3677-4e1f-addf-8ae2b060a6b0"

$ cd ../cluster-access && terraform apply access.tfplan
azurerm_role_assignment.deploy_cluster_user: Creation complete after 28s
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### How the pipeline reaches the cluster: the whole chain

**In one line:** the deploy job proves itself twice: to Azure with the OIDC token, then to Kubernetes with a certificate that Azure hands out.

```
 deploy job (environment "production", after my approval)
    │ 1. OIDC token from GitHub (subject …:environment:production)
    v
 Entra ID ── matches the federated credential? ──> Azure token for id-…-deploy
    │ 2. az aks get-credentials
    v
 Azure ── does id-…-deploy have "Cluster User Role" on this cluster? ──> kubeconfig file
    │ 3. kubectl apply …  (the kubeconfig holds a client certificate)
    v
 Kubernetes API of aks-evgenia-k8s-dev
```

| Step | Who checks | Proof used |
| --- | --- | --- |
| GitHub to Azure | Entra ID | The OIDC token, against the federated credential |
| Azure to the cluster's details | Azure, by role | The Azure token, against the role assignment |
| Into Kubernetes | The cluster itself | A **client certificate**: a file signed by the cluster that says who the holder is |

**The known gap: the certificate means full admin.** This cluster has no Entra ID integration. Then Kubernetes knows nothing about Azure identities: it only checks certificates, and the certificate Azure hands out is the cluster's admin certificate. Azure has no way to give out "only the `restauranty` namespace".

What keeps the risk small:

- Only the deploy job can get the certificate, only on `main`, and only after I approve.
- The runner is a fresh machine that GitHub throws away after the job, together with the file.

What it does not fix: the certificate itself is valid for a long time. If someone copied it during a deploy, it would keep working until the cluster's certificates are replaced (`az aks rotate-certs`). That is an accepted risk for this week.

**What production would do:** turn on Entra ID integration with Azure RBAC on the cluster and switch off local accounts. Then Kubernetes checks Azure identities itself, and the deploy identity can get the role "Azure Kubernetes Service RBAC Writer" on the `restauranty` namespace only. Even better is **GitOps**: a tool inside the cluster (Argo CD) pulls the wanted state from git, so the pipeline needs no cluster rights at all.

### 31. GitHub: the approval gate and branch protection

**In one line:** two settings on GitHub. Deploys wait for my approval, and nobody changes `main` without a pull request.

**Environment `production`** (repo → Settings → Environments):

| Setting | Value | What it protects |
| --- | --- | --- |
| Required reviewers | `springlaughing` | The deploy job waits until I click "Approve". Before that, GitHub does not even issue the job's OIDC token. |
| Deployment branches | `main` only | A job from any other branch cannot use this environment, so it can never match the deploy identity's rule |

**Branch protection on `main`** (repo → Settings → Branches):

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | On | Every change to `main` goes through a pull request, so the pipeline's checks run first |
| Required approvals | 0 | I work alone: requiring an approval would stop me from merging my own work |
| Force pushes | Off | Nobody can rewrite `main`'s history |

**Read back with the GitHub API**, to check the settings really are what I think:

```
$ gh api repos/springlaughing/restauranty-devsecops-aks/environments \
    --jq '.environments[] | {name, reviewers: [.protection_rules[] | select(.reviewers) | .reviewers[].reviewer.login]}'
{"name":"production","reviewers":["springlaughing"]}

$ gh api repos/springlaughing/restauranty-devsecops-aks/environments/production/deployment-branch-policies --jq '.branch_policies[].name'
main

$ gh api repos/springlaughing/restauranty-devsecops-aks/branches/main/protection \
    --jq '{approvals: .required_pull_request_reviews.required_approving_review_count, enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled}'
{"approvals":0,"enforce_admins":false,"force_push":false}
```

**Two doors left open for the admin (me), on purpose:**

- `enforce_admins: false`: as repo admin I could still push straight to `main`.
- The environment allows admins to skip the approval.

Normal for a one-person project. Production would close both, so the rules hold for everyone.

### 32. The workflow, part by part

**In one line:** one file, `.github/workflows/ci-cd.yaml`, with two jobs: `build` (four times, once per component) and `deploy`.

Two kinds of variables appear in it:

- `${{ … }}` is filled in by GitHub before the step runs. Example: `${{ matrix.component }}` becomes `auth`.
- `$NAME` is a normal shell variable, read when the command runs. Example: `$IMAGE`.

**When it runs:**

```yaml
name: ci-cd

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:
```

| Trigger | Meaning |
| --- | --- |
| `pull_request` to `main` | Every pull request: build and test only |
| `push` to `main` | A merge: build, push, then deploy after approval |
| `workflow_dispatch` | A "Run workflow" button in GitHub, to start it by hand. From a feature branch, Entra ID refuses the sign-in, which is a useful test. After a cluster rebuild, a run on `main` puts the newest images back. |

**Rights, and fixed values:**

```yaml
permissions:
  contents: read

env:
  AZURE_TENANT_ID: 84f58ce9-43c8-4932-b908-591a8a3007d3
  AZURE_SUBSCRIPTION_ID: daf9c53c-7096-4293-9bb1-f7ad8263db1a
  PIPELINE_CLIENT_ID: d708b138-ba0b-44a0-beae-5c0cb5bcf9ea   # id-evgenia-restauranty-pipeline
  DEPLOY_CLIENT_ID: f4f5b9dd-3677-4e1f-addf-8ae2b060a6b0     # id-evgenia-restauranty-deploy
  ACR_NAME: acrevgeniarestauranty
  REGISTRY: acrevgeniarestauranty.azurecr.io
  CLUSTER_NAME: aks-evgenia-k8s-dev
  CLUSTER_RESOURCE_GROUP: rg-evgenia-k8s-dev
  APP_URL: https://restauranty.aks.springlaughing.dev
```

| Part | Meaning |
| --- | --- |
| `permissions: contents: read` | Every job may only read the code by default. Each job asks for more only if it needs it. GitHub gives each job a token for the GitHub API; this keeps that token weak. |
| `env` | Values every job can read. The tenant (my Entra directory), the subscription, and the two client ids are **not secrets**: without a federated credential that matches the job, they open nothing. So no GitHub secrets are needed at all. |

**Job 1, `build`: who, where, how often:**

```yaml
  build:
    name: build ${{ matrix.component }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    strategy:
      fail-fast: false
      matrix:
        include:
          - { component: auth, path: backend/auth }
          - { component: discounts, path: backend/discounts }
          - { component: items, path: backend/items }
          - { component: client, path: client }
    env:
      IMAGE: acrevgeniarestauranty.azurecr.io/${{ matrix.component }}:${{ github.sha }}
```

| Part | Meaning |
| --- | --- |
| `runs-on: ubuntu-latest` | A fresh Linux machine from GitHub for each run, with Docker, Node.js, the Azure CLI and kubectl already installed |
| `id-token: write` | May ask GitHub for an OIDC token. Without this, the Azure sign-in cannot work. |
| `matrix` | Run the same job four times, once per component, side by side. `component` and `path` change in each copy. |
| `fail-fast: false` | If one component fails, the other three still finish, so one run shows every problem |
| `IMAGE` | The image's full name, for example `acrevgeniarestauranty.azurecr.io/auth:2b75634…`. The tag is the commit's full id (`github.sha`). |

**Why the commit id as the tag.** Each image says exactly which code it was built from, and a tag never moves. The usual alternative, `latest`, points at a different image after every push, so nobody can tell what is really running.

**Job 1, `build`: the steps:**

```yaml
      - uses: actions/checkout@v7

      - uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: ${{ matrix.path }}/package-lock.json

      - name: Install dependencies
        working-directory: ${{ matrix.path }}
        run: npm ci

      - name: Test
        working-directory: ${{ matrix.path }}
        run: |
          if [ "${{ matrix.component }}" = client ]; then
            CI=true npm test -- --watchAll=false
          else
            node --check app.js
            node --check server.js
          fi

      - name: Build image
        run: docker build -t "$IMAGE" "${{ matrix.path }}"
```

| Step | What it does |
| --- | --- |
| `actions/checkout` | Copies the repo's code onto the runner |
| `actions/setup-node` | Installs Node.js 22, the same major version as the images (`node:22-alpine`). `cache: npm` keeps downloaded packages between runs, keyed by the lock file, so the next run is faster. |
| `npm ci` | Installs exactly the versions in `package-lock.json`, nothing newer. `npm install` could pick newer versions and change the lock file. |
| Test, client | Runs the client's component test (`src/App.test.jsx`: the start page shows the logo and the welcome text). `CI=true` and `--watchAll=false` make it run once and stop, instead of waiting for file changes. |
| Test, backends | They have no tests. `node --check` at least proves every file parses: a typo fails the build. The real checks for them are the security tests after the deploy (#13). |
| `docker build` | Builds the image from the component's own `Dockerfile` (entry 11) |

**Job 1, `build`: push, on `main` only:**

```yaml
      - name: Sign in to Azure as the pipeline identity
        if: github.event_name != 'pull_request'
        uses: azure/login@v3
        with:
          client-id: ${{ env.PIPELINE_CLIENT_ID }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}

      - name: Push image
        if: github.event_name != 'pull_request'
        run: |
          az acr login --name "$ACR_NAME"
          docker push "$IMAGE"
```

| Part | Meaning |
| --- | --- |
| `if: github.event_name != 'pull_request'` | Skipped on pull requests. A pull request never signs in to Azure and never pushes. |
| `azure/login` | Microsoft's action. With only a client id and no secret, it uses OIDC: it asks GitHub for the token and trades it at Entra ID (the steps in "How GitHub signs in to Azure") |
| `az acr login` | Uses the Azure sign-in to get a short-lived password for the registry, and gives it to Docker |
| `docker push` | Uploads the image. The identity has AcrPush, so this works, and nothing else does. |

**Job 2, `deploy`: conditions and the approval gate:**

```yaml
  deploy:
    name: deploy to AKS
    needs: build
    if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: production
      url: ${{ env.APP_URL }}
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    permissions:
      contents: read
      id-token: write
```

| Part | Meaning |
| --- | --- |
| `needs: build` | Starts only after all four builds succeeded. One failed build means no deploy. |
| `if: … refs/heads/main` | Only for `main`, never for a pull request |
| `environment: production` | The approval gate (entry 31). The job waits until I approve. The OIDC token then carries the subject `…:environment:production`, which is the only subject the deploy identity accepts. `url` puts a link to the site on the run's page. |
| `concurrency` | At most one deploy at a time. A second one waits; `cancel-in-progress: false` means a running deploy is never stopped halfway. |

**Job 2, `deploy`: the steps:**

```yaml
      - uses: actions/checkout@v7

      - name: Sign in to Azure as the deploy identity
        uses: azure/login@v3
        with:
          client-id: ${{ env.DEPLOY_CLIENT_ID }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}

      - name: Get the cluster's credentials
        run: az aks get-credentials --resource-group "$CLUSTER_RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

      - name: Point the manifests at this commit's images
        run: |
          sed -i -E "s#(${REGISTRY}/(auth|discounts|items|client)):[0-9a-f]+#\1:${GITHUB_SHA}#" k8s/app/*.yaml
          grep -n "image:" k8s/app/*.yaml

      - name: Deploy
        run: |
          kubectl apply -f k8s/app/ -f k8s/network/
          for d in auth discounts items client; do
            kubectl rollout status "deployment/$d" -n restauranty --timeout=5m
          done

      - name: Smoke test
        run: |
          curl -fsS -o /dev/null -w "website %{http_code}\n" "$APP_URL/"
          curl -fsS -w "\n" "$APP_URL/api/auth"
```

| Step | What it does |
| --- | --- |
| Sign in as the deploy identity | Same as above, with the other client id. Works only in the approved `production` job. |
| `az aks get-credentials` | Writes the kubeconfig file, so `kubectl` can reach the cluster (the chain above) |
| `sed …` | The manifests in git name a fixed tag (`:bfb0e27`). This replaces it with this run's commit id, in the runner's copy only; git is not changed. The pattern matches only the four app images: MongoDB's `mongo:8.0.34` stays as it is. `grep` prints the result into the log, as a record. |
| `kubectl apply` | Sends the app's manifests and the network rules (Part 6) to the cluster. Kubernetes changes only what differs. |
| `kubectl rollout status` | Waits until each Deployment runs its new pods and they are ready, up to 5 minutes each. If a new version does not start, the job fails. |
| Smoke test | Two quick checks that the site answers: the home page and auth. `-f` makes `curl` fail on an error answer, so the job fails too. |

**What the pipeline does not deploy.** The platform parts (the Gateway, cert-manager, External Secrets, Reloader, the flood limit) are still installed by `scripts/setup-aks.sh`. They change rarely and need Helm. The pipeline handles what changes often: the app.

**A known gap: the tag in git.** The manifests in git keep the tag `bfb0e27`. After a cluster rebuild, `scripts/setup-aks.sh` deploys that old tag. Fix for now: after a rebuild, start the workflow by hand on `main` ("Run workflow"), which deploys the newest images.

### When the pipeline deploys, and how production teams do it

**In one line:** the pipeline deploys after a **merge**, never after a pull request, and only when I approve. Several merges can go out in one deploy, which is one of the normal ways production teams work, with one risk to watch.

#### Which jobs run, by event

What starts the run decides what the run does:

| What I do | Event | Build (4 jobs) | Push to the registry | Deploy |
| --- | --- | --- | --- | --- |
| Open a pull request, or add commits to it | `pull_request` | Runs | Skipped | Skipped |
| Merge the pull request into `main` | `push` to `main` | Runs | Runs | **Waits for my approval**, then runs |
| "Run workflow" on `main` | `workflow_dispatch` | Runs | Runs | Waits for my approval, then runs |
| "Run workflow" on another branch | `workflow_dispatch` | Runs | Refused by Entra ID (entry 36) | Skipped |

Two lines in the workflow decide this:

```yaml
# build job, the two push steps:
if: github.event_name != 'pull_request'

# deploy job:
if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
environment: production          # makes the job wait for my approval
```

**Where to see it:** the **Actions** tab in GitHub lists every run with its event. A run that waits for me shows a yellow clock and a **"Review deployments"** button, and GitHub sends me an email, because I am the required reviewer. In the terminal:

```
$ gh run list --limit 5          # the event column: pull_request, push, workflow_dispatch
$ gh run view <run id>           # which jobs ran, were skipped, or wait
```

So every pull request shows the pipeline twice: while it is open (build only), and after the merge (build, push, then deploy after my click). If I do not click, nothing is deployed. **"Reject"** ends the run without a deploy.

#### Several merges, one deploy

`main` grows with every merge: each merge adds to everything before it. Each run builds and deploys exactly its own commit. Suppose I merge three times without approving:

| Merge | Run | Deploys, if I approve it |
| --- | --- | --- |
| A | Run 1 builds A, the deploy waits | The code up to A |
| B | Run 2 builds A+B, the deploy waits | The code up to A+B |
| C | Run 3 builds A+B+C, the deploy waits | The code up to **A+B+C** |

Approving run 3 puts all three merges live at once. Nothing is lost, because its images contain everything.

**The risk: an old waiting run.** If run 1 still waits and I approve it later by mistake, it deploys the **older** code. That is an accidental rollback: B and C disappear from production. So: reject old waiting deploys. Planned for #13: a check in the deploy job that stops if `main` has already moved past the run's commit.

**Docs-only merges.** Every merge asks to deploy, even one that changes only documentation. That builds four new images from the same code and restarts every pod for nothing. The image tag is the commit id, so every merge gives every image a new name, and Kubernetes rolls out new pods. Planned for #13: the workflow ignores changes that touch only `docs/`, `notes/` and `*.md` files.

#### How production teams do it

There are three common styles:

| Style | How it works | Who uses it |
| --- | --- | --- |
| **Continuous deployment** | Every merge goes live automatically, with no click. Safety comes from good tests, gradual rollouts (a few users first), feature flags (new code switched off until ready) and fast rollback. | Many web companies. They deploy many times a day. |
| **Continuous delivery with approval** (this project) | Every merge produces a version that could go live; a person decides when it does. Several merges often go out together, like A+B+C above. | Banks, healthcare and other regulated fields, and teams with fixed release times |
| **GitOps** | Merging a change into a deployment repo **is** the deploy. A tool inside the cluster (Argo CD) sees the change and applies it, so the pipeline needs no rights in the cluster. | Many Kubernetes teams |

Two principles almost all of them share:

1. **Small batches are safer.** If one deploy carries one change and something breaks, it is clear which change caused it. If it carries ten, someone has to search. The DORA research on software delivery keeps finding that teams who deploy small changes often have fewer failed deployments, not more. Batching A+B+C is fine now and then, but not as a habit.
2. **Build once, then promote the same image.** In a typical setup a merge deploys to a **staging** environment first, tests run there, and the approval promotes the **same** image to production. Nothing is rebuilt for production, so production runs exactly what was tested.

**Where this project stands.** Continuous delivery with approval. It matches the brief's "on merges to main (or manual approval)", and it shows a person in control. There is no staging before the approval, so my click means "I trust the build and the scans". The pipeline already builds once per commit, tagged with the commit id. So adding staging later would be one more deploy job that uses the same images, not a new build.

**An approval is only as good as what the approver checks.** In a regulated team, the reviewer looks at the test results, the scan results and the list of changes before clicking. Once #13 adds Trivy and `npm audit` to the same run, my click has real information behind it.

### 33. First run: the pull request

**In one line:** the first run, on the pull request itself, built and tested all four components and correctly skipped the deploy.

```
$ gh run view 42882192526 --json jobs --jq '.jobs[] | "\(.conclusion)\t\(.name)"'
success   build discounts    20s
success   build items        17s
success   build client       68s
success   build auth         20s
skipped   deploy to AKS
```

| Result | What it shows |
| --- | --- |
| Four builds `success` | All four install, pass their test or syntax check, and build their image on a clean machine, not just on my laptop |
| client takes longest (68 s) | It is the only one with a real test, and the React build is the heaviest |
| `deploy` `skipped` | A pull request never deploys. It never signed in to Azure either: those steps were skipped too |

### 34. First run on main: Entra ID refused the sign-in

**In one line:** after the merge, all three build jobs that reached the sign-in were refused by Entra ID. GitHub sends a different subject than the rule expected. The protection worked; the rule was wrong.

**What the run showed** (from the run's page in GitHub):

```
build auth
AADSTS700213: No matching federated identity record found for presented assertion subject
'repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:ref:refs/heads/main'.
Check your federated identity credential Subject, Audience and Issuer against the presented assertion.
```

`AADSTS700213` is Entra ID's code for "no federated credential matches this token". The images were built but not pushed, and the deploy did not start.

**The difference:**

| | Subject |
| --- | --- |
| The rule in Terraform | `repo:springlaughing/restauranty-devsecops-aks:ref:refs/heads/main` |
| What GitHub sent | `repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:ref:refs/heads/main` |

GitHub adds the numeric **id** of the account (`31309521`) and of the repo (`1450795318`). This is called the **immutable subject**: a name can change owner, an id cannot.

**Why that matters.** With names only, the rule trusts "whoever owns a repo called `springlaughing/restauranty-devsecops-aks`". If I renamed or deleted my account, someone else could register `springlaughing`, create a repo with the same name, and Azure would accept their jobs as mine. This is sometimes called **repo-jacking**. The ids belong to my account and this repo forever, so a look-alike gets different numbers and is refused.

**How I checked it.** GitHub's API shows the exact prefix it uses for this repo:

```
$ gh api repos/springlaughing/restauranty-devsecops-aks/actions/oidc/customization/sub
{"use_default":true,"use_immutable_subject":true,
 "sub_claim_prefix":"repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318"}
```

**The fix** (branch `12-oidc-subject`): the variable `github_repo` became `github_subject_prefix`, which holds that exact prefix. Both rules use it:

```hcl
variable "github_subject_prefix" {
  description = "Start of the OIDC subject GitHub sends for this repo: repo:<owner>@<owner id>/<repo>@<repo id>."
  type        = string
  default     = "repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318"
}

subject = "${var.github_subject_prefix}:ref:refs/heads/main"         # push identity
subject = "${var.github_subject_prefix}:environment:production"      # deploy identity
```

The plan changes only the two subjects, in place, and creates or deletes nothing:

```
$ terraform plan -out persistent.tfplan
  ~ subject = "repo:springlaughing/restauranty-devsecops-aks:environment:production"
           -> "repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:environment:production"
  ~ subject = "repo:springlaughing/restauranty-devsecops-aks:ref:refs/heads/main"
           -> "repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:ref:refs/heads/main"
Plan: 0 to add, 2 to change, 0 to destroy.
```

**Lesson:** a refusal is the security working. The first run on `main` proved that Entra ID accepts only an exact subject: a near miss is refused like a stranger.

**Also fixed: a warning about Node.js 20.** The same run warned that `actions/checkout@v4`, `actions/setup-node@v4` and `azure/login@v2` are built for Node.js 20, which GitHub is phasing out. The workflow now uses `actions/checkout@v7`, `actions/setup-node@v7` and `azure/login@v3`, which run on Node.js 24. Before changing, I checked in each new version's `action.yml` that it runs on Node 24 and still has every input the workflow uses (`node-version`, `cache`, `cache-dependency-path`, `client-id`, `tenant-id`, `subscription-id`).

### 35. First deploy by the pipeline

**In one line:** after the subject fix, "Re-run failed jobs" on the same run pushed the four images and, after my approval, deployed them. The app now runs images built by the pipeline, not on my laptop.

**Why re-run instead of a new commit.** The re-run uses the same commit and builds the same images. The only thing that changed between the two attempts is the rule in Azure. So if it works now, the rule was the only cause.

```
$ gh run view 42884263301 --json headSha,attempt,jobs --jq '...'
commit ff7a2e0, attempt 2
success   build items
success   build client
success   build auth
success   build discounts
success   deploy to AKS
```

**The deploy job's log, shortened:**

```
k8s/app/auth.yaml:122:      image: acrevgeniarestauranty.azurecr.io/auth:ff7a2e0019d48f0fe92329fffb4152681afd2f69
k8s/app/client.yaml:65:     image: acrevgeniarestauranty.azurecr.io/client:ff7a2e0019d48f0fe92329fffb4152681afd2f69
k8s/app/discounts.yaml:122: image: acrevgeniarestauranty.azurecr.io/discounts:ff7a2e0019d48f0fe92329fffb4152681afd2f69
k8s/app/items.yaml:131:     image: acrevgeniarestauranty.azurecr.io/items:ff7a2e0019d48f0fe92329fffb4152681afd2f69
k8s/app/mongodb.yaml:134:   image: mongo:8.0.34
deployment.apps/auth configured
...
deployment "auth" successfully rolled out
deployment "discounts" successfully rolled out
deployment "items" successfully rolled out
deployment "client" successfully rolled out
website 200
"Auth Server UP!"
```

| Line | What it shows |
| --- | --- |
| `image: …:ff7a2e0…` | The `sed` step pointed the four app images at this commit's images. MongoDB's image stayed as it was. |
| `configured` | `kubectl` found a difference and updated the object. For the Deployments that is the new image. For objects whose file did not change, it only updates `kubectl`'s own notes on the object. |
| `successfully rolled out` | Each Deployment's new pods started and are ready |
| `website 200`, `"Auth Server UP!"` | The smoke test: the site and auth answer through the Gateway |

**What runs in the cluster now:**

```
$ kubectl get pods -n restauranty -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,STARTED:.status.startTime
auth-674d47786b-lrtpx        auth:ff7a2e0019d48f0fe92329fffb4152681afd2f69        2026-11-10T19:27:51Z
client-b9b54c75f-qvlk2       client:ff7a2e0019d48f0fe92329fffb4152681afd2f69      2026-11-10T19:27:37Z
discounts-568d5fd7d4-pbmsz   discounts:ff7a2e0019d48f0fe92329fffb4152681afd2f69   2026-11-10T19:27:45Z
items-8646b745b6-kgx4c       items:ff7a2e0019d48f0fe92329fffb4152681afd2f69       2026-11-10T19:27:40Z
mongodb-0                    mongo:8.0.34                                         2026-11-10T12:34:24Z
...
```

MongoDB was not restarted: its pod is from the morning, and its history still has one revision. Only the four app components changed.

**Nothing broke.** The network test from #11 on the new images:

```
$ ./scripts/test-network.sh
...
15 passed, 0 failed
```

The login still reaches MongoDB, every attack is still blocked, and no app ServiceAccount can read Secrets.

**What this proves for #12:**

| Goal from the issue | Proof |
| --- | --- |
| An identity with a federated credential for `main` only | Entra refused the first attempt (entry 34) and accepted only the exact subject |
| AcrPush, images tagged with the commit | Four images `…:ff7a2e0…` in the registry, pushed by the pipeline |
| Build, test, push, deploy | All five jobs `success` |
| No secrets stored in GitHub | The workflow holds only ids; the repo has no Actions secrets (`gh api …/actions/secrets` → `total_count: 0`) |
| A run from a feature branch is refused by Entra | Entry 36 |
| Role scoped to my resource group and AKS | Push identity: the registry only. Deploy identity: this cluster only |
| Branch protection on `main` | Read back in entry 31 |

### 36. Proof: a run from a feature branch is refused

**In one line:** the same workflow, started by hand on the branch `12-oidc-subject`, built and tested everything, then Entra ID refused its sign-in. A branch other than `main` cannot push an image or reach the cluster.

**Why this test.** A pull request never tries to sign in (entry 32), so it proves nothing about Azure. "Run workflow" on a feature branch does try. This is what an attacker who can push a branch, but not merge to `main`, would get.

```
$ gh workflow run ci-cd.yaml --ref 12-oidc-subject
$ gh run view 42886007123 --json jobs --jq '.jobs[] | "\(.conclusion)\t\(.name)"'
failure   build items
failure   build client
failure   build discounts
failure   build auth
skipped   deploy to AKS

$ gh run view 42886007123 --log-failed | grep AADSTS
AADSTS700213: No matching federated identity record found for presented assertion subject
'repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318:ref:refs/heads/12-oidc-subject'
```

The steps of one build job:

```
success   Run actions/checkout@v7
success   Run actions/setup-node@v7
success   Install dependencies
success   Test
success   Build image
failure   Sign in to Azure as the pipeline identity
skipped   Push image
```

| Result | What it shows |
| --- | --- |
| Install, test, build: `success` | Anyone may build and test on any branch, with the new action versions too |
| Sign-in: `failure`, subject `…:ref:refs/heads/12-oidc-subject` | Entra ID trusts the push identity only for `refs/heads/main`. Any other branch is refused. |
| Push: `skipped` | No image from a feature branch reaches the registry |
| Deploy: `skipped` | The deploy job runs only for `main` and only in the environment `production` |

The red "failure" on this run is the expected result: here, failing is the proof.

### What #12 creates

| Thing | Where | State |
| --- | --- | --- |
| Deploy identity `id-evgenia-restauranty-deploy` | `terraform/persistent/github.tf` | Applied |
| GitHub rules: `main` for the push identity, `environment:production` for the deploy identity | `terraform/persistent/github.tf` | Applied |
| Deploy identity's role on the cluster | `terraform/cluster-access/pipeline.tf` | Applied |
| Environment `production` with me as required reviewer, `main` only | GitHub settings | Set |
| Branch protection: pull request required for `main` | GitHub settings | Set |
| Workflow: build, test, push, deploy after approval, smoke test | `.github/workflows/ci-cd.yaml` | First deploy done (commit `ff7a2e0`) |

---

## What is next

| Task | Issue |
| --- | --- |
| docker-compose for local dev | #1 |
| Backends reconnect to MongoDB by themselves | #28 |
| Pipeline security gates: Trivy, Semgrep, npm audit, tests after the deploy | #13 |
| Monitoring, alerts, the attack demo | #14, #15 |
