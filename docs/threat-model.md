# Threat model: Restauranty on AKS

**What this is.** A list of the ways this system can be attacked, and for each one: what was built against it, how that was proven, and what it still does not stop. It sits next to the [security assessment](security-assessment.md), which found the problems in the app as I received it, and the [build log](build-log.md), which records how each fix was built and tested. This document keeps the reasoning; the other two keep the evidence.

**How to read it.** Part 1 explains the idea behind it in a few lines. Part 2 shows the system and the places where trust changes. Part 3 tells 16 attacks as short stories, each in the same five parts. Part 4 sorts every threat by trust boundary and by type (STRIDE), with its state today. Part 5 lists what is accepted on purpose.

**State:** 11 November 2026, after issues #4 to #15 and #28.

---

## Contents

- [Part 1. The idea: assume breach](#part-1-the-idea-assume-breach)
- [Part 2. The system and its trust boundaries](#part-2-the-system-and-its-trust-boundaries)
- [Part 3. Sixteen attacks, one story each](#part-3-sixteen-attacks-one-story-each)
- [Part 4. STRIDE per trust boundary](#part-4-stride-per-trust-boundary)
- [Part 5. Accepted on purpose](#part-5-accepted-on-purpose)
- [Sources for the real cases](#sources-for-the-real-cases)

---

## Part 1. The idea: assume breach

Every protection can fail one day: a bug in a library, a stolen password, a poisoned package. So this project does not only ask "how do I keep attackers out?", but also "**when** one gets in, how far can they go, and will I notice?". This way of thinking is called **assume breach**.

For each attack, that gives three questions:

- **Prevent:** what stops it at the door?
- **Contain:** if it gets past the door, what limits the damage?
- **Detect:** does someone find out, and how fast?

A protection is only counted when it was **proven** with a test: a request that should be refused, sent for real, and its answer saved.

---

## Part 2. The system and its trust boundaries

**What runs.** Restauranty is a restaurant back office: a React website (`client`) and three Node.js services (`auth` for logins and users, `discounts` for coupons, `items` for the menu and orders), with one MongoDB database. It runs on Azure Kubernetes Service (AKS). One Gateway (NGINX) receives every request from the internet. Secrets live in Azure Key Vault. A GitHub pipeline builds, scans and deploys.

```
 internet ─TB1─> Gateway ─TB2─> client, auth, discounts, items ─TB3─> MongoDB
                 (HTTPS,                        │
                  limits)                       └─TB4─> Key Vault, Entra ID, Cloudinary

 GitHub pipeline, admins ───────────────────────────────> Azure and the cluster
```

**What a trust boundary is.** A place where something crosses from a side I trust less to a side I trust more. There, the more trusted side stops assuming and starts checking: **who sent this** (authentication), **may they do this** (authorization), and **is it what it claims to be** (validation). A missing check at a boundary is a threat.

Being inside does not mean being trusted. By default, every pod in a Kubernetes cluster can call every other pod, so "it came from inside the cluster" says nothing about who sent it. Every request is checked where it is received. This is called **zero trust**.

| Boundary | Less trusted side | More trusted side | Why it is a boundary |
| --- | --- | --- | --- |
| TB1 | anyone on the internet | the Gateway, the first part I control | fully untrusted input enters here, and the caller is unknown |
| TB2 | the Gateway and every other pod | the services' code and data | the Gateway checks HTTPS, the path and the rate, but not who the user is; each service checks the login token itself |
| TB3 | service code, which handles untrusted input | all stored data | a taken-over service must not mean the whole database |
| TB4 | the cluster's identities | Azure (Key Vault, Entra ID) and Cloudinary | different owners: the cluster must prove who it is, and Cloudinary is another company |
| Pipeline, admins | GitHub and the people with access | Azure and the cluster | the most powerful access comes from outside: whoever controls the pipeline or an admin account can change everything |

---

## Part 3. Sixteen attacks, one story each

Each story has five parts: **how the attacker gets there**, **a real case** (checked against the sources at the end), **what I built**, **how it is proven**, and **what it does not stop**. "Entry" means an entry in the [build log](build-log.md); "F" a finding in the [security assessment](security-assessment.md).

### 1. Reading private data without logging in

**How the attacker gets there.** They call the API directly, without the website. On day one, `GET /api/auth/users` answered anyone with every user's email, address, phone, role and **password hash** (F11). Items, orders, coupons and campaigns were readable too (F12).

**Real case.** Optus, Australia, 2022: an attacker sent requests to an API that did not properly check who was asking, and took the personal details of up to 9.8 million customers (the government's figure; the privacy regulator later counted 9.5 million).

**What I built.** Three layers, so one can fail: the Gateway refuses the user list in any spelling (entry 27); every data route asks for a login token (entry 7); and no answer contains a password hash anymore (entry 6).

**How it is proven.** The same requests as on day one now get 403 or 401 (assessment Retests 1 and 2; entry 29). The pipeline repeats them after every deploy (entry 42). The dashboard counts anyone who still asks for the user list (entry 62).

**What it does not stop.** Every account is an admin (F1, accepted): anyone who signs up can read everything through the normal app.

### 2. Changing data without permission

**How the attacker gets there.** The same as story 1, with `POST`, `PUT` and `DELETE`. On day one, anyone could create a 100% coupon valid until 2099, change the menu, and delete users (F13, F14).

**Real case.** US Postal Service, 2018: any logged-in user of usps.com could ask an API for other users' account data, about 60 million accounts by the researcher's estimate, and in some cases change it. The flaw had been reported a year earlier.

**What I built.** A token check on every route that writes (entry 7), and the frontend sends the token (assessment test 4c).

**How it is proven.** Creating, changing and deleting without a token now gets 401 (assessment Retest 2), and the pipeline repeats it after every deploy (entry 42).

**What it does not stop.** Logged-in users can do everything (F1). There is no record of **which user** changed what: the Gateway's log has the IP address and the path, not the user (accepted).

### 3. Making your own admin token

**How the attacker gets there.** The login token was signed with one shared secret (HS256), and the server ran with `MySecret1!`, the example value printed in the project's README (F9). With it, anyone can sign a token that says "I am admin".

**Real case.** Uber, 2016: attackers found cloud credentials written into code in a private GitHub repository, and used them to take data of 57 million users and drivers. A secret that sits where code is shared is not a secret.

**What I built.** A key pair (RS256): only `auth` holds the private key that signs; the other services get only the public key, which can check a token but not make one (entry 3). Both keys live in Key Vault, and each service may read only its own (entries 17 to 19).

**How it is proven.** A token forged with the old secret was accepted before (200) and is refused now (401; assessment Retest 1).

**What it does not stop.** Whoever gets the private key, from `auth`'s pod or from Key Vault with an admin account, can sign tokens again. Tokens stay valid for 6 hours even after logout (F7, accepted).

### 4. Guessing passwords

**How the attacker gets there.** They try many passwords against the login. On day one there was no limit: about 10 guesses per second (F6). Weak passwords like `Password1` were accepted (F5), and the answer showed which emails exist (F4).

**Real case.** 23andMe, 2023: attackers logged in with passwords leaked from other websites ("credential stuffing"). About 14,000 accounts were opened directly; through a feature that shares data between relatives, data of about 6.9 million people was exposed. The company said its own systems were not broken into.

**What I built.** The Gateway lets one IP address try 10 logins per minute, plus a burst of 5, and answers the rest with 429 (entry 27). An unknown email and a wrong password get the same answer, in the same time (entry 5). An alert fires at more than 20 failed logins in 5 minutes (entry 58).

**How it is proven.** A k6 attack: 481 guesses in 4 minutes; the Gateway refused 436, 45 reached the login, and Slack said "35 failed logins in 5 minutes" (entry 61).

**What it does not stop.** The limit is per IP address: an attacker with many addresses gets 10 tries per minute **each**. The alert still fires, because it counts in total. Stopping that needs a lock per account, multi-factor login, or a check against leaked passwords. Weak passwords are still accepted (F5, accepted).

### 5. Cracking stolen password hashes

**How the attacker gets there.** They get the password hashes (story 1 gave them to anyone) and guess passwords on their own computer, as fast as it allows, unseen. In the assessment, 4 of 5 test passwords were recovered in 3.4 seconds (F11).

**Real case.** LinkedIn, 2012: 6.5 million password hashes were posted on a forum. They were unsalted SHA-1, a fast hash; about 3.5 million of 5.8 million unique hashes were cracked within days. In 2016, a larger dump from the same breach appeared.

**What I built.** No answer contains a password hash anymore: the user model leaves the field out by default (entry 6). The hashes use bcrypt, which is slow on purpose.

**How it is proven.** The user list, one user, and the delete answer contain no hash (assessment Retest 1: 0 of 7 users).

**What it does not stop.** Whoever gets the database itself (a backup, a disk, MongoDB's password) gets the hashes. Weak passwords fall quickly even to bcrypt (F5).

### 6. Personal data in logs and tokens

**How the attacker gets there.** They read a place that nobody thinks of as sensitive. The server wrote addresses and phone numbers into its log on every page load (F3). The login token carries email, address and phone, readable by anyone who holds it: a token is encoded, not encrypted (F2).

**Real case.** Twitter, 2018: a bug wrote users' passwords into an internal log before they were hashed. Twitter found it itself, saw no misuse, and asked all of its more than 330 million users to consider changing their password.

**What I built.** The lines that printed personal data are removed (entry 6). Logs are kept 7 days and are readable only in Grafana, behind its login (entry 50).

**How it is proven.** The server log after the fix (entry 6).

**What it does not stop.** The token still carries personal data (F2, accepted: the profile page reads it). The Gateway's log stores visitors' IP addresses, which are personal data under the GDPR (entry 54).

### 7. Secrets in the git history

**How the attacker gets there.** They read the repository's history. A secret that was committed once stays there, even after it is deleted from the files. Here: old `.env` files with a MongoDB password (F10), and Cloudinary keys in the first commit (F20).

**Real case.** Toyota, 2022: an access key to a customer database sat in a public GitHub repository for about five years, from December 2017 to September 2022, with 296,019 customers' email addresses behind it.

**What I built.** No secret in git: every secret lives in Key Vault and reaches the cluster through External Secrets (entries 17 to 19). gitleaks checks every push and the whole history, and a pull request cannot be merged while it fails (entries 38, 40).

**How it is proven.** gitleaks is a required check on every pull request (entry 40).

**What it does not stop.** The old secrets stay in the history; only rotating them helps. Those are the course repository's and were never used here (F20, not reported: a shared course project).

### 8. One part gets more access than it needs

**How the attacker gets there.** They take over one part and use **its** rights. If one identity can read every secret, taking over any service means taking over everything.

**Real case.** Capital One, 2019: a misconfigured web firewall running in AWS was made to hand out the cloud credentials of its role. That role could read storage with data of about 100 million people in the US and 6 million in Canada.

**What I built.** One Azure identity per workload, each with a role on **single secrets**: `items` may read the Cloudinary keys, `auth` the private key, nobody everything (entries 17 to 19). The same for Grafana and Alertmanager (entries 52, 57). Monitoring tools whose charts could read every Secret in the cluster were narrowed (entry 51), and so was the Trivy Operator (entry 63).

**How it is proven.** `items` asked Key Vault for `auth`'s private key and was refused by Azure itself: `403 ForbiddenByRbac` (entry 19).

**What it does not stop.** Some components must be trusted with a lot: External Secrets and cert-manager can read every Secret in the cluster, and so can the Prometheus Operator's role (entry 51). Whoever holds the cluster's admin credentials can do anything (story 14).

### 9. A known hole in a package

**How the attacker gets there.** A vulnerability is published (a CVE). Attackers scan the internet for systems still running the old version, often within days.

**Real case.** Equifax, 2017: a hole in Apache Struts (CVE-2017-5638) was published with a fix in March 2017. Equifax ran a scan that did not find the vulnerable version on the system that was exposed. Attackers got in from mid-May and stayed unnoticed for 76 days; data of about 148 million people was taken.

**What I built.** Four layers. The pipeline's gate: Trivy blocks a CRITICAL before a deploy, `npm audit` checks the libraries (entry 37). Dependabot proposes updates (entry 44). A nightly scan re-checks what runs against that day's list of vulnerabilities (entry 43). And the Trivy Operator scans the images **running** in the cluster, whenever a pod starts, also images the pipeline never builds (entries 63 to 65).

**How it is proven.** An old base image was stopped by the gate, and the merge was blocked (entry 45). The Trivy Operator found a CRITICAL in MongoDB's image, which nothing had scanned before, and the alert reached Slack (entry 64).

**What it does not stop.** Holes nobody knows yet ("zero-days"). Software a scanner cannot see: a program copied into an image without a package manager may be missing from its parts list (entry 45). And the time between "reported" and "fixed": a scanner only informs; someone still has to rebuild and deploy. MongoDB's CRITICAL is known and documented, and waits for a newer image.

### 10. A poisoned package or image

**How the attacker gets there.** They do not attack the app; they poison something it is built from: a library, a base image, a tool in the pipeline.

**Real cases.** event-stream, 2018: a popular npm library was handed over to a stranger, who added a dependency with hidden code that stole from one specific Bitcoin wallet app. xz-utils, 2024: a maintainer known as "Jia Tan" spent years earning trust, then hid a backdoor in a compression library used by Linux systems (CVE-2024-3094, rated 10.0); an engineer noticed slow SSH logins and found it before it spread widely. Trivy, March 2026: attackers with stolen credentials changed the version tags of Trivy's GitHub Action to point to code that stole pipeline secrets, and published poisoned images (build log, Part 9).

**What I built.** Everything is named by its fingerprint, not by a version name: pipeline actions by commit SHA, tools and images by digest, deploys by digest (Part 9, entry 41). npm checks every library against the hash in `package-lock.json` (entry 30); install scripts are off (`npm ci --ignore-scripts`). The job that runs npm code holds no Azure identity (entry 37). The security scanner itself is pinned too, in the pipeline and in the cluster (entry 65).

**How it is proven.** The digests in the cluster were checked against two registries and against the pipeline's own pin (entry 65).

**What it does not stop.** A poisoned version that I adopt on purpose, for example through a Dependabot update. Images are not signed, so the cluster cannot check who built them; signing and a check before start are in the plan ("What is next"). Security tools are high-value targets precisely because they're trusted and widely installed: being a "security" tool earns them no exemption ("Can a security tool be trusted?").

### 11. A taken-over pod moves sideways

**How the attacker gets there.** They take over one container (story 9 or 10) and use it as a base to reach other parts: the database, other services, the cloud's metadata address.

**Real cases.** Tesla, 2018: a Kubernetes console without a password let attackers into a pod that held cloud credentials, and they used Tesla's cloud to mine cryptocurrency. MongoBleed, 2025 (CVE-2025-14847): a MongoDB hole that leaks memory **before** login, exploited in the wild, fixed in 8.0.17; this cluster runs 8.0.34. A database reachable from any pod is only as safe as its last unknown bug.

**What I built.** Network rules (NetworkPolicies, enforced by Cilium): every pod in `restauranty` refuses everything by default; then only the paths the app uses are opened (entries 20 to 25). Only the three backends may reach MongoDB; only `items` may reach the internet, on HTTPS, and not the cloud's metadata address (169.254.169.254).

**How it is proven.** Attacker pods tried 15 paths; every forbidden one was refused, and the app still worked (entry 25). Before the rules, an attacker pod reached MongoDB; its password held (entry 24).

**What it does not stop.** An admin can delete the rules: that is the job of access rights, not of the network. `items` may reach **any** public address on HTTPS, not only Cloudinary. The namespaces `gateway`, `monitoring` and `trivy-system` have no rules yet ("What is next"). A `kubectl port-forward` with admin credentials goes around the rules (entry 54).

### 12. Escaping the container to the node

**How the attacker gets there.** From inside a container, they use a flaw in the container runtime or the Linux kernel to reach the node, and with it every pod on it.

**Real case.** runc, 2019 (CVE-2019-5736): a process in a container could overwrite the program that starts containers on the host, and then run code as root on the node. Advisories named running containers as a non-root user as one of the ways to block it.

**What I built.** Every app pod runs as a normal user, without Linux capabilities, without privilege escalation, with a seccomp filter and, where possible, a read-only file system (entries 11, 15). The namespace `restauranty` **enforces** this ("restricted" Pod Security): a pod that breaks it is refused, even one added later by mistake. The monitoring tools run under "baseline", which refuses host access (entry 50).

**How it is proven.** The pods' settings, and Kubernetes refusing pods that break the profile (entry 15).

**What it does not stop.** A kernel flaw that works even from a non-root container. Trivy's scan jobs run as root on purpose, in their own namespace (entry 63).

### 13. Listening in on the connection

**How the attacker gets there.** They sit on the same network as a user, an open café Wi-Fi for example, and read or change traffic that is not encrypted.

**Real case.** Firesheep, 2010: a Firefox add-on that let anyone on an open Wi-Fi take over other people's Facebook and Twitter sessions with a double-click, because those sites encrypted only the login, not the rest. It pushed large sites to use HTTPS everywhere.

**What I built.** HTTPS only, with a Let's Encrypt certificate; plain HTTP is redirected (entry 15). The domain ends in `.dev`, which browsers only open over HTTPS.

**How it is proven.** A request over plain HTTP gets a redirect to HTTPS (entry 15).

**What it does not stop.** Traffic **inside** the cluster, from the Gateway to the services and to MongoDB, is not encrypted. A service mesh with mutual TLS would encrypt it ("What is next" in the plan).

### 14. Taking over the pipeline

**How the attacker gets there.** The pipeline can push images and deploy them. Whoever controls it, or steals what it holds, controls production.

**Real cases.** Codecov, 2021: from January to April, an altered upload script sent the environment variables of customers' pipelines, where tokens and keys usually live, to the attackers. CircleCI, 2023: malware on an engineer's laptop stole a logged-in session, and every customer was told to rotate every secret stored there.

**What I built.** No passwords or keys are stored in GitHub: jobs sign in to Azure with short-lived tokens (OIDC) (entry 30). Two identities: one may only push images, and only for the `main` branch; the other may only deploy, and only after my approval (entries 30, 31). A run from another branch is refused by Azure itself (entry 36). `main` accepts changes only through pull requests with passing checks, without exceptions for admins (entry 40). Actions are pinned by commit SHA (Part 9).

**How it is proven.** A run from a feature branch was refused by Entra ID (entry 36).

**What it does not stop.** The deploy identity gets the cluster's admin credentials, because the cluster has no Entra ID integration (entry 30). Whoever takes over my GitHub account can approve deploys. Planned: Entra ID on the cluster, or GitOps, so the pipeline needs no rights on the cluster at all.

### 15. An attack nobody notices

**How the attacker gets there.** Most attacks are not stopped at the door; they are found later, or never. The longer nobody notices, the more is taken.

**Real case.** Equifax, again: attackers queried databases for 76 days. A device meant to inspect the traffic was not checking encrypted traffic, partly because a certificate it needed had expired. My own small case: after a cluster restart, the backends lost MongoDB, every pod looked healthy, and every login failed (entry 23; fixed in entry 46).

**What I built.** Prometheus for numbers, Loki for logs, Grafana for the dashboard (entries 47 to 55). Ten alert rules that reach a Slack channel: password guessing, refused tokens, server errors, services down, MongoDB down or full, and a CRITICAL in a running image (entries 57, 58). On day one, attacks were answered with "500" and looked like outages (F8); now they get 401, so the two can be told apart (entry 4).

**How it is proven.** The k6 attack reached Slack (entry 61), and so did the Trivy finding (entry 64).

**What it does not stop.** Attacks that only show in logs have no alert yet: Loki has no rule engine connected ("What is next"). Nobody is on call: an alert in Slack at night waits until morning. Grafana itself is reached with one shared admin password, without multi-factor login; Entra ID is planned (#17).

### 16. A secret leaked: now what?

**How the attacker gets there.** It does not matter how: a laptop, a log, a backup. A secret is out, and every minute it stays valid is a minute it can be used.

**Real case.** CircleCI, 2023 (story 14): the answer to a leak was "rotate everything", and every customer had to do it by hand.

**What I built.** All secrets live in one place, Key Vault. A changed value reaches the cluster within an hour, or at once with a forced sync, and Reloader restarts the services that use it (entries 19, 52). The login keys can be replaced in Key Vault without touching the code.

**How it is proven.** A forced sync of Grafana's password (entry 52).

**What it does not stop.** There is no tested runbook yet for rotating the MongoDB password under load, with zero failed requests (#16, "What is next"). A rotated JWT key logs every user out.

---

## Part 4. STRIDE per trust boundary

**STRIDE** is a checklist of six kinds of threat: **S**poofing (pretending to be someone else), **T**ampering (changing data), **R**epudiation (acting without a trace), **I**nformation disclosure (leaking data), **D**enial of service (overloading), **E**levation of privilege (gaining more rights). Each trust boundary gets the six questions.

**State:** **Done** = built and proven; **Partly** = built, with a known gap; **Accepted** = known, not fixed, with a reason (Part 5); **Open** = planned.

### TB1: internet → Gateway

| | Threat | What protects | State | Proof |
| --- | --- | --- | --- | --- |
| S | Guessing passwords on the login | Login limit per IP; alert on failed logins | Partly (many IPs) | entry 61; story 4 |
| S | Logging in to Grafana with its admin password | Strong password in Key Vault; lockout after 5 failures; no sign-up | Partly: no MFA, Entra ID planned (#17) | entries 52, 53 |
| T | Reading or changing traffic | HTTPS only, HTTP redirected | Done | entry 15; story 13 |
| R | Acting without a trace | Gateway access log (IP, path, status) in Loki, 7 days | Done | entries 54, 61 |
| I | The user list with password hashes | Blocked at the Gateway in any spelling; token check; no hashes in answers | Done | entries 6, 7, 27, 29; story 1 |
| I | Other websites calling the API (`CORS: *`) | Login tokens travel in a header, not in a cookie, so another website cannot use a visitor's login by itself | Accepted | Part 5 |
| I | The HTTPS private key | Only in the `gateway` namespace; copy in Key Vault | Partly: cert-manager and External Secrets can read all Secrets | entry 15 |
| D | Flooding the app | Flood limit per IP (50 per second, burst 100) | Partly: no DDoS protection | entry 29 |
| E | Anyone who signs up is admin | none | Accepted (F1) | Part 5 |

### TB2: Gateway and pods → services

| | Threat | What protects | State | Proof |
| --- | --- | --- | --- | --- |
| S | A pod calls a service directly, around the Gateway | Network rules: services accept only the Gateway (and Prometheus on `/metrics`) | Done | entry 25; story 11 |
| S | A forged login token | RS256: only `auth` can sign | Done | Retest 1; story 3 |
| T | Writing without a token | Token check on every route | Done | Retest 2; entry 42 |
| R | Nobody knows which user changed what | Gateway log has IP and path, not the user | Accepted | Part 5 |
| R | Attacks answered with 500, looking like outages | 401 for token errors, one short log line | Done | entry 4 |
| I | Logged-in users receive every password hash | Hashes left out of every answer | Done | entry 6 |
| I | Personal data inside the token | none | Accepted (F2) | Part 5 |
| D | One service starves the others | CPU and memory requests and limits | Done | entry 15 |
| E | Escaping a container | Non-root, no capabilities, seccomp, "restricted" enforced | Done | entries 11, 15; story 12 |

### TB3: services → MongoDB

| | Threat | What protects | State | Proof |
| --- | --- | --- | --- | --- |
| S | Any pod connects to MongoDB | Network rule: only the three backends; MongoDB login required | Done | entries 24, 25 |
| T | One service changes another's data | none: one shared database user | Accepted | Part 5 |
| R | Nobody knows who changed data in the database | none | Accepted | Part 5 |
| I | The database password leaks | Only in Key Vault, delivered by External Secrets | Done | entries 17 to 19 |
| I | A copied disk is read | Azure encrypts managed disks at rest by default | Partly: not checked with a command | — |
| D | MongoDB down, or its disk full | Alerts: disconnected, down, disk over 80% | Done | entries 46, 58 |
| E | The app's database user does more | `readWrite` on the app's database only | Done | entry 15 |

### TB4: cluster → Key Vault, Entra ID, Cloudinary

| | Threat | What protects | State | Proof |
| --- | --- | --- | --- | --- |
| S | A pod reads another service's secrets | One identity per workload (Workload Identity) | Done | entry 19; story 8 |
| T | Someone changes a secret in Key Vault | Only my account may write; workload identities may only read | Done | entries 16, 18 |
| R | Nobody knows who read a secret | Key Vault's diagnostic logs are not switched on | Open | — |
| I | Services get the Cloudinary keys they do not need | Only `items` may read them | Done | entry 18 |
| I | Pods read the synced Kubernetes Secrets | App pods have no Kubernetes token | Partly: trusted controllers read all | entry 15; story 8 |
| D | Key Vault cannot be reached | External Secrets keeps the last value; the app keeps running | Accepted | entry 19 |
| E | An identity reading Key Vault gets more | Roles on single secrets, never on the whole vault | Done | entry 18 |

### Pipeline and admins

| | Threat | What protects | State | Proof |
| --- | --- | --- | --- | --- |
| S | Stolen Azure keys stored in GitHub | No keys stored: OIDC, trusted only for `main` or the `production` environment | Done | entries 30, 36 |
| S | An admin account taken over | Multi-factor login on my accounts | Partly: not shown in the evidence | — |
| T | A vulnerable or poisoned image shipped | Gates, pins by SHA and digest, deploy by digest, nightly and in-cluster scans | Partly: images not signed | entries 37 to 45, 63 to 65; stories 9, 10 |
| T | Changes to `main` without review | Pull requests only, required checks, no admin exception | Done | entry 40 |
| I | App secrets in the pipeline | None stored in GitHub | Done | entry 30 |
| E | The pipeline controls everything | Two identities: push only, deploy only after approval | Partly: the deploy identity gets admin on the cluster | entry 30; story 14 |

---

## Part 5. Accepted on purpose

Each of these is known, written down, and not fixed this week, for the reason given. The full list with the production answer goes into `SECURITY.md`.

- **Every new account is an admin** (F1). The frontend is an admin back office; in production, new accounts would start as normal users.
- **Personal data inside the login token** (F2). The profile page reads it from the token; in production the token would carry only the user's id and role.
- **Weak passwords are accepted** (F5). Offline guessing is closed (story 5) and online guessing slowed (story 4); in production, at least 12 characters and a check against leaked passwords.
- **Logout does not end the token** (F7). Tokens expire after 6 hours; in production, short tokens and a way to revoke them.
- **CORS allows every website.** The token is sent in a header that the app's code sets, not in a cookie the browser adds by itself, so another website cannot act with a visitor's login. Still worth narrowing to the app's own address.
- **One shared database user** for the three backends, and **no record of who changed what**, in the app or in the database.
- **Traffic inside the cluster is not encrypted** (story 13).
- **No protection against large floods** from many addresses (DDoS); that needs Azure's DDoS protection or a web application firewall.
- **If Key Vault is unreachable,** the app keeps running with the last values; new values wait.
- **MongoDB's image has a known CRITICAL** (Go 1.24.6 inside it), until a newer image is used (entry 64).

---

## Sources for the real cases

- Optus 2022: [UpGuard](https://upguard.com/news/optus-data-breach-exposes-up-to-9-8-million-customers-details), [BankInfoSecurity](https://www.bankinfosecurity.com/optus-attacker-halts-au15-million-extortion-attempt-a-20157)
- US Postal Service 2018: [Engadget](https://www.engadget.com/2018-11-21-usps-patches-api-flaw-that-exposed-data-on-60-million-users.html), [Sophos](https://news.sophos.com/en-us/2018/11/23/hacker-says-usps-ignored-serious-security-flaw-for-over-a-year)
- Uber 2016: [SecurityWeek](https://www.securityweek.com/uber-hacked-information-57-million-users-accessed-covered-breach/), [TechTarget](https://www.techtarget.com/cybersecurity/news/450430575/Uber-breach-affected-57-million-users-covered-up-for-a-year?amp=1)
- 23andMe 2023: checked on 10 November 2026 (company statements as reported in the press); see the build log's section on rate limiting
- LinkedIn 2012: [SANS Internet Storm Center](https://isc.sans.edu/diary/13390), [KoreLogic](https://korelogic.com/blog/2016/05/19/linkedin-2012-hash-analysis)
- Twitter 2018: [TechCrunch](https://techcrunch.com/2018/05/03/twitter-password-bug/), [Engadget](https://www.engadget.com/2018/05/03/twitter-warns-users-change-passwords-following-bug/)
- Toyota 2022: [TechCrunch](https://techcrunch.com/2022/10/12/toyota-customer-email-addresses-exposed/), [The Register](https://www.theregister.com/2022/10/11/toyota_source_code_email_leak/)
- Capital One 2019: [TechTarget](https://www.techtarget.com/cybersecurity/news/252467901/Capital-One-hack-highlights-SSRF-concerns-for-AWS?amp=1)
- Equifax 2017: [Fortune, on the GAO report](https://fortune.com/2018/12/10/equifax-hack-lasted-for-76-days-compromised-148-million-people-government-report-says), [Dark Reading](https://www.darkreading.com/attacks-breaches/gao-says-equifax-missed-flaws-intrusion-in-massive-breach), [SecurityWeek](https://www.securityweek.com/attackers-made-9000-unauthorized-database-queries-equifax-hack-report/)
- event-stream 2018: [Snyk](https://snyk.io/blog/a-post-mortem-of-the-malicious-event-stream-backdoor), [The Register](https://www.theregister.com/2018/11/26/npm_repo_bitcoin_stealer/)
- xz-utils 2024: [Snyk](https://snyk.io/blog/the-xz-backdoor-cve-2024-3094/), [InfoQ](https://www.infoq.com/news/2024/04/xz-backdoor/)
- Trivy 2026: see the build log, Part 9, "Pinning" (StepSecurity, Endor Labs, CVE-2026-33634)
- Tesla 2018: [CNBC](https://www.cnbc.com/2018/02/21/hackers-hijack-teslas-cloud-system-to-mine-cryptocurrency-redlock.html), [Fortune](https://fortune.com/2018/02/20/tesla-hack-amazon-cloud-cryptocurrency-mining/amp/)
- MongoBleed 2025: [Tenable](https://www.tenable.com/blog/cve-2025-14847-mongobleed-mongodb-memory-leak-vulnerability-exploited-in-the-wild), [Arctic Wolf](https://arcticwolf.com/resources/blog/cve-2025-14847)
- runc 2019: [Tenable](https://www.tenable.com/blog/cve-2019-5736-exploits-the-common-runc-container-binary-to-escape-to-host), [Ubuntu security notice](https://ubuntu.com/security/vulnerabilities/runc)
- Firesheep 2010: [eWeek](https://www.eweek.com/security/firefox-firesheep-extension-exposes-dangers-of-lack-of-encryption/), [Hackaday](https://hackaday.com/2010/10/25/firesheep-promoting-privacy-in-a-scary-way)
- Codecov 2021: [Codecov's statement](https://about.codecov.io/security-update/), [Rapid7](https://www.rapid7.com/blog/post/2021/04/16/codecov-discloses-supply-chain-compromise/)
- CircleCI 2023: checked on 10 November 2026 (CircleCI's incident report as reported in the press)
