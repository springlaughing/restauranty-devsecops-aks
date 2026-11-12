# Restauranty: DevSecOps on AKS

**What this is.** My final project for the Ironhack DevOps bootcamp. I received Restauranty, a restaurant back office (a React website and three Node.js services with MongoDB). I tested its security first, then ran it on Azure Kubernetes Service (AKS) with a security layer around it: fixes in the code, rules at the edge and inside the cluster, secrets in a vault, security checks in the pipeline, and alerts.

**Live:** https://restauranty.aks.springlaughing.dev (only while the cluster runs; might not be available after bootcamp finishes).

---

## The story in one minute

**Day one.** One request, with no login, returned every user's password hash and personal data. From those hashes, 4 of 5 test passwords were recovered in 3.4 seconds. The server also signed login tokens with `MySecret1!`, a value published in the repository, so anyone could make their own admin token.

**What I did about it,** in the order I built it:

1. **Test.** A security assessment along the OWASP Web Security Testing Guide found 20 problems, 8 of them high.
2. **Close.** Fix the code, so the problems are gone at their source.
3. **Contain.** Assume an attacker gets in anyway, and limit how far they can go: rules at the Gateway, network rules between pods, one identity per service for secrets.
4. **Guard.** Make the pipeline test for it, so it cannot come back unnoticed.
5. **Detect.** If an attack is tried, an alert reaches Slack.

**Result.** Of the 20 problems, 14 are fixed or contained. 5 are accepted on purpose, with the reason and the production answer in [SECURITY.md](SECURITY.md). 1 belongs to the original repository's owner (keys in its old git history).

---

## Before and after

The same test, on the app as I received it and on the system today.

| Test | Before | After |
| --- | --- | --- |
| Read the user list, with no login | 200: every user, with password hash | 403: closed at the Gateway, in any spelling |
| Make an admin token with the published secret | Accepted | 401: only `auth` holds the signing key |
| Create a 100% coupon with no login | Created | 401: every data route needs a token |
| 20 wrong logins in a row from one address | 20 answered, no limit | 5 answered, 15 refused with 429 |
| A hacked pod connects to MongoDB | Open | Blocked by network rules |
| `items` asks Key Vault for `auth`'s signing key | Every service had the one shared secret | 403: each service reads only its own secrets |
| A pull request adds a package with a CRITICAL vulnerability | No pipeline | The build fails and the merge is blocked |
| 200 made-up URLs sent to the API | 201 new series in Prometheus: the monitoring can be flooded | 0 new series |
| 481 password guesses in 4 minutes (k6) | Nobody notices | 436 refused at the Gateway; Slack alert: "35 failed logins in 5 minutes" |

The test outputs are in [docs/evidence](docs/evidence): for example [10-edge-before.txt](docs/evidence/10-edge-before.txt) and [10-edge-after.txt](docs/evidence/10-edge-after.txt) for the Gateway, [11-network-before.txt](docs/evidence/11-network-before.txt) and [11-network-after.txt](docs/evidence/11-network-after.txt) for the network rules.

---

## What it does not protect against yet

The system is safer, not safe. The biggest open points, all on the plan:

- **The cluster login is an admin certificate,** on my laptop and in the pipeline's deploy job. Whoever copies it controls the cluster, around every network rule.
- **Images are not signed,** so the cluster cannot check that an image was built by the pipeline.
- **Some attacks show only on the dashboard,** with no alert, and nobody is on call at night.
- **Every new account is an admin** (a demo shortcut), so anyone who signs up can manage the restaurant through the normal app.

The full list, with what is accepted on purpose and why, is in [SECURITY.md](SECURITY.md).

---

## The documents

Each one stands on its own. Start with the approach if you want the idea, with the assessment if you want the problems.

- [**Our approach**](docs/approach.md): the idea and the method behind the project, and the standards followed (OWASP, STRIDE).
- [**Security assessment**](docs/security-assessment.md): the 20 problems in the app as I received it, each proven with a real request, and the retests after the fixes.
- [**Threat model**](docs/threat-model.md): 16 ways to attack the system, each as a short story with a real case from the news; then every threat by trust boundary, with its state today.
- [**Build log**](docs/build-log.md): how each part was built and tested, step by step, with the commands and their output. Ends with the plan for what is next.
- [**SECURITY.md**](SECURITY.md): how to report a problem, what is accepted on purpose, the known gaps, and the personal data the app keeps (GDPR).
- [**CONTRIBUTING.md**](CONTRIBUTING.md): how work is planned, branched, committed and merged.

---

## Architecture

![The system on AKS: the browser reaches the Gateway, which routes to client, auth, discounts and items; these use MongoDB. External Secrets reads Key Vault with one identity per service. GitHub Actions deploys. Red dashed lines mark the four trust boundaries.](docs/images/trust-boundary.png)

**How a request travels.** The browser connects over HTTPS to the **Gateway** (NGINX Gateway Fabric), the only door from the internet. The Gateway holds the Let's Encrypt certificate, closes the user list, and limits logins and floods. It sends each path to its service: `/` to `client` (the React website, served by nginx), `/api/auth` to `auth` (signup, login, users), `/api/items` to `items` (menu and orders) and `/api/discounts` to `discounts` (coupons and campaigns). The three backends store their data in **MongoDB**, which runs in the cluster on its own disk. `items` stores menu photos at Cloudinary.

**Where the secrets come from.** No secret is in git or in the pipeline. They live in **Azure Key Vault**. External Secrets copies each one into the cluster, using a separate Azure identity per service, and each identity may read only its own secrets.

**How code gets there.** A merge to `main` starts **GitHub Actions**. It logs in to Azure with a short-lived token (OIDC), so no Azure password is stored in GitHub. It builds the four images, runs the security checks, pushes the images to Azure Container Registry, and deploys after I approve.

**How problems are seen.** **Prometheus** collects the services' metrics, **Loki** collects the logs, **Grafana** shows both, and **Alertmanager** sends alerts to Slack. **Trivy Operator** scans the images that are really running.

Grafana's login through Entra ID ("SSO" in the picture) is planned (#17), not built yet: today Grafana has one local admin account.

The red dashed lines are **trust boundaries**: places where data crosses from a side I trust less to a side I trust more. The [threat model](docs/threat-model.md#part-2-the-system-and-its-trust-boundaries) explains each one.

---

## What was built, and where the proof is

Every part started as an issue and was merged through a pull request (PR). The build log has the details and the test output.

### Close: fixes in the code

- **Login tokens signed with a key pair (RS256).** Only `auth` holds the private key that signs; the other services check with the public key, which cannot sign. A forged token is refused, and token errors answer 401 instead of 500. Issue [#4](https://github.com/springlaughing/restauranty-devsecops-aks/issues/4), PR [#22](https://github.com/springlaughing/restauranty-devsecops-aks/pull/22). Proof: [Retest 1](docs/security-assessment.md#retests).
- **No password hashes in any answer, no personal data in the logs.** Issue [#21](https://github.com/springlaughing/restauranty-devsecops-aks/issues/21), PR [#22](https://github.com/springlaughing/restauranty-devsecops-aks/pull/22).
- **A login token on every data route,** and the website sends it. Issue [#9](https://github.com/springlaughing/restauranty-devsecops-aks/issues/9), PR [#23](https://github.com/springlaughing/restauranty-devsecops-aks/pull/23). Proof: [API tests](docs/evidence/13-api-security-tests.txt).
- **Metrics counted by route, not by full URL,** so junk requests cannot flood Prometheus (F18). Issue [#14](https://github.com/springlaughing/restauranty-devsecops-aks/issues/14), PR [#56](https://github.com/springlaughing/restauranty-devsecops-aks/pull/56). Proof: [Retest 3](docs/security-assessment.md#retests).
- **Backends restart until MongoDB is ready,** instead of running broken after a cluster start. Issue [#28](https://github.com/springlaughing/restauranty-devsecops-aks/issues/28), PR [#53](https://github.com/springlaughing/restauranty-devsecops-aks/pull/53). Proof: [before](docs/evidence/28-mongo-reconnect-before.txt), [after](docs/evidence/28-mongo-reconnect-after.txt).

### Run it on AKS

- **Hardened images:** non-root users, no development tools, no HIGH or CRITICAL vulnerabilities at build time. Issue [#5](https://github.com/springlaughing/restauranty-devsecops-aks/issues/5), PR [#25](https://github.com/springlaughing/restauranty-devsecops-aks/pull/25).
- **The cluster:** AKS with Workload Identity and Cilium network rules, built with my Terraform modules from an earlier project. Issue [#6](https://github.com/springlaughing/restauranty-devsecops-aks/issues/6). The long-lived parts (Key Vault, registry, static IP, DNS) are in [terraform/persistent](terraform/persistent), PR [#24](https://github.com/springlaughing/restauranty-devsecops-aks/pull/24).
- **The app on AKS, with HTTPS:** manifests, MongoDB, Gateway routing, Let's Encrypt. Issue [#7](https://github.com/springlaughing/restauranty-devsecops-aks/issues/7), PR [#26](https://github.com/springlaughing/restauranty-devsecops-aks/pull/26).

### Contain: limit what an attacker can reach

- **Secrets from Key Vault, one identity per service.** Issue [#8](https://github.com/springlaughing/restauranty-devsecops-aks/issues/8), PR [#27](https://github.com/springlaughing/restauranty-devsecops-aks/pull/27). Proof: [items is refused auth's key](k8s/proof/items-asks-for-auth-secret.yaml) (403 ForbiddenByRbac).
- **Network rules:** everything is denied in the app's namespace, then only the app's own paths are opened. Issue [#11](https://github.com/springlaughing/restauranty-devsecops-aks/issues/11), PR [#29](https://github.com/springlaughing/restauranty-devsecops-aks/pull/29). Proof: 15 of 15 tests, [before](docs/evidence/11-network-before.txt) and [after](docs/evidence/11-network-after.txt).
- **Rules at the Gateway:** the user list closed in any spelling, 10 logins per minute per address, a flood limit. Issue [#10](https://github.com/springlaughing/restauranty-devsecops-aks/issues/10), PR [#30](https://github.com/springlaughing/restauranty-devsecops-aks/pull/30). Proof: 11 of 11 tests, [before](docs/evidence/10-edge-before.txt) and [after](docs/evidence/10-edge-after.txt).

### Guard: security checks in the pipeline

- **A pipeline with no stored Azure keys,** two identities (push only, deploy only), and a deploy that waits for approval. Issue [#12](https://github.com/springlaughing/restauranty-devsecops-aks/issues/12), PRs [#31](https://github.com/springlaughing/restauranty-devsecops-aks/pull/31) and [#32](https://github.com/springlaughing/restauranty-devsecops-aks/pull/32).
- **Security gates:** gitleaks (secrets), Semgrep (risky code), npm audit and Trivy (known vulnerabilities), a list of every package in each image (SBOM), API security tests and an OWASP ZAP scan after each deploy, and a nightly rescan of the running images. Tools and actions are pinned by hash. Issue [#13](https://github.com/springlaughing/restauranty-devsecops-aks/issues/13), PR [#33](https://github.com/springlaughing/restauranty-devsecops-aks/pull/33). Proof: a test PR with a CRITICAL package, [blocked](docs/evidence/13-trivy-block-pr.png).

### Detect: see attacks and failures

- **Monitoring:** Prometheus, Grafana, Loki and Alloy, with a dashboard for traffic and security. Issue [#14](https://github.com/springlaughing/restauranty-devsecops-aks/issues/14), PR [#55](https://github.com/springlaughing/restauranty-devsecops-aks/pull/55).
- **Alerts to Slack,** a password-guessing attack with k6 to test them, and Trivy Operator scanning the running images. Issue [#15](https://github.com/springlaughing/restauranty-devsecops-aks/issues/15), PR [#58](https://github.com/springlaughing/restauranty-devsecops-aks/pull/58). Proof: [the k6 alert in Slack](docs/evidence/15-k6-alert-slack.png).

### Documents

- **Security assessment:** issue [#2](https://github.com/springlaughing/restauranty-devsecops-aks/issues/2). **Threat model:** issue [#3](https://github.com/springlaughing/restauranty-devsecops-aks/issues/3), PR [#59](https://github.com/springlaughing/restauranty-devsecops-aks/pull/59). **This README and SECURITY.md:** issue [#19](https://github.com/springlaughing/restauranty-devsecops-aks/issues/19).

---

## Repository map

- `backend/auth`, `backend/discounts`, `backend/items`: the three Node.js services, each with its own Dockerfile.
- `client`: the React website, built into static files and served by nginx.
- `k8s/platform`: the Gateway, HTTPS certificates, External Secrets, rate limits.
- `k8s/app`: the app itself: the four services, MongoDB, routes, the Gateway rules.
- `k8s/network`: the network rules between pods.
- `k8s/monitoring`: settings for Prometheus, Grafana, Loki, Alloy, Alertmanager, Trivy Operator, and the alert rules.
- `k8s/proof`: test pods for the network and secret tests.
- `terraform/persistent`: what survives a cluster rebuild: Key Vault, container registry, static IP, DNS records, the pipeline's identities.
- `terraform/cluster-access`: what the cluster may do in Azure, and the identity of each service. Applied again after every rebuild.
- `scripts`: `setup-aks.sh` installs everything on the cluster; `test-*.sh` are the security tests; `k6` holds the password-guessing attack.
- `.github/workflows`: the pipeline, the secret scan, and the nightly scan.
- `docs`: the documents above, with `evidence` (test outputs and screenshots) and `images`.

---

## Run it locally

Requires **Node.js 20 or newer** (tested on Node 24) and Docker.

**1. Start MongoDB.**

```bash
docker run -d --name my-mongo -p 27017:27017 -v mongo-data:/data/db mongo:8
```

**2. Create the token keys.** Login tokens are signed with RS256: a key pair instead of one shared secret. `auth` signs with the private key. `discounts` and `items` check tokens with the public key, which cannot create tokens. A service without a valid key refuses to start. `*.pem` files are git-ignored.

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt-private.pem
openssl pkey -in jwt-private.pem -pubout -out jwt-public.pem
```

**3. Write each service's settings.** Copy `.env.example` to `.env` in each backend folder, then write the keys into the `.env` files, one line each:

```bash
# set_key <file> <variable> <pem file>: replaces the variable's line with the key on one line
set_key() {
  grep -v "^$2=" "$1" > "$1.tmp"
  printf '%s="%s"\n' "$2" "$(awk '{printf "%s\\n", $0}' "$3")" >> "$1.tmp"
  mv "$1.tmp" "$1"
}
set_key backend/auth/.env      JWT_PRIVATE_KEY jwt-private.pem
set_key backend/discounts/.env JWT_PUBLIC_KEY  jwt-public.pem
set_key backend/items/.env     JWT_PUBLIC_KEY  jwt-public.pem
```

The settings each service reads:

- `JWT_PRIVATE_KEY` (auth only): the private key that signs login tokens.
- `JWT_PUBLIC_KEY` (discounts, items): the public key that checks login tokens.
- `JWT_ISSUER`, `JWT_AUDIENCE` (all): who issues the token and who it is for, checked on every request. Example: `restauranty-auth`, `restauranty-api`.
- `MONGODB_URI` (all): the database address. Example: `mongodb://127.0.0.1:27017/restauranty`.
- `CLOUD_NAME`, `CLOUD_API_KEY`, `CLOUD_API_SECRET` (items): a Cloudinary account, for menu images. Creating an item needs it.
- `PORT` (all): 3001 for auth, 3002 for discounts, 3003 for items.
- For the website: `REACT_APP_API_URL=http://localhost:80`.

**4. Start each service,** each in its own terminal:

```bash
cd backend/auth && npm install && npm start
cd backend/discounts && npm install && npm start
cd backend/items && npm install && npm start
cd client && npm install && npm start
```

**5. Start HAProxy,** which sends each path to its service, like the Gateway on AKS:

```bash
haproxy -f haproxy.cfg
```

Open **http://localhost/**.

---

## Run it on AKS

This is how my deployment is set up; the names are mine and would change for another account. Each step is explained in the [build log](docs/build-log.md), Parts 2 to 5.

**You need:** an AKS cluster with the OIDC issuer, Workload Identity and Cilium network rules switched on, `kubectl` pointing at it, and the tools `az`, `kubectl`, `helm`, `terraform`, `openssl` and `jq`.

```bash
# Once: Key Vault, container registry, static IP, DNS records, the pipeline's identities
cd terraform/persistent && terraform apply

# After every cluster rebuild: what the cluster may do in Azure, and one identity per service
cd terraform/cluster-access && terraform apply

# Everything on the cluster: Gateway, certificates, secrets, the app, network rules, monitoring
./scripts/setup-aks.sh
```

**Secrets.** Put these into Key Vault before the first run: the token keys (`jwt-private-key`, `jwt-public-key`), the app's database password (`mongo-password`, hex only, because it goes into a URL), the three Cloudinary keys, and a Slack webhook for the alerts. `setup-aks.sh` creates the MongoDB admin password and Grafana's admin password by itself. It stops with a message if the database password, the Cloudinary keys or the Slack webhook are missing.

**Images.** After that, the pipeline builds, scans and deploys every merge to `main`, after approval.

**Security tests,** against the live system:

```bash
./scripts/test-edge.sh           # the Gateway rules
./scripts/test-network.sh        # the network rules (needs the test pods from k8s/proof)
./scripts/test-api-security.sh   # the API: logins, tokens, the user list
```

---

## Tech stack

- **App:** React 18 and Tailwind CSS; Node.js with Express, Mongoose, jsonwebtoken and bcryptjs; MongoDB 8; Cloudinary for images.
- **Cloud:** Azure Kubernetes Service with Cilium, Azure Key Vault, Azure Container Registry, Entra ID Workload Identity; Terraform.
- **In the cluster:** NGINX Gateway Fabric, cert-manager with Let's Encrypt, External Secrets, Reloader.
- **Pipeline:** GitHub Actions with OIDC; gitleaks, Semgrep, npm audit, Trivy, CycloneDX SBOM, OWASP ZAP; Dependabot.
- **Monitoring:** Prometheus, Alertmanager, Grafana, Loki, Alloy, Trivy Operator; Slack for alerts; k6 for the attack test.
