# Security policy

**What this is.** How to report a security problem, what is accepted on purpose, what was simplified for the demo, which gaps are still open, and what personal data the app keeps. The reasoning behind each point is in the [threat model](docs/threat-model.md); the proof is in the [build log](docs/build-log.md) and the [security assessment](docs/security-assessment.md). "Entry" means an entry in the build log; "F" a finding in the assessment.

**State:** 12 November 2026.

---

## Reporting a problem

**Please report privately, not in a public issue.** On GitHub, open the **Security** tab of this repository and choose **Report a vulnerability**. Only I can read the report. Describe what you did, what happened, and what you expected.

This is a bootcamp project run by one person, so there is no fixed answer time. I aim to reply within a week. Please give me time to fix the problem before you publish it; 90 days is the common rule.

**Why the findings in this repository are public.** The [security assessment](docs/security-assessment.md) describes the app as I received it from the course, tested on my laptop with fake users. Its problems are fixed, contained or accepted below, and the original code is public anyway. A new problem in the deployed system is different: report it privately first.

---

## Accepted on purpose

**In one line:** known, tested, and not fixed this week, each for a reason. For each: what it is, why it is accepted, and what a production system would do.

**The app manages its own logins.**
It stores password hashes and signs its own tokens.
Why accepted: replacing the login system is a project of its own. The hashes are bcrypt and never leave the database (entry 6); the signing key is a key pair kept in Key Vault (entries 3, 18).
Production: an identity service such as Entra External ID or Keycloak. The app would then store no passwords at all, and the service would rotate the signing keys.

**Every new account is an admin (F1).**
Why accepted: the frontend is a back office for restaurant staff, and its pages only show for admins. Without this shortcut, nobody could use the demo.
Production: new accounts start as normal users; admins are set up separately.

**The user management routes are closed for everyone, not checked by role.**
`auth` can list, show, change and delete users. A role check ("only admins") would be the right fix, but with F1 everyone is an admin, so it would protect nothing. Instead, the Gateway refuses these routes for every caller (entry 27). Only someone with rights on the cluster can reach them, with `kubectl port-forward`.
Production: fix F1 first, then a role check in `auth`.

**Personal data inside the login token (F2).**
A login token is only encoded, not encrypted. Anyone who holds a token can read the email, name, address and phone number in it.
Why accepted: the profile page reads these fields from the token.
Production: the token carries only the user's id and role; the profile page asks the server.

**Weak passwords are accepted (F5).**
`Password1` is allowed.
Why accepted: the two ways to guess passwords are closed or slowed. Offline guessing needs the password hashes, and no answer contains them any more. Online guessing is limited at the Gateway: each IP address gets 10 logins per minute, after that the answer is 429 "too many requests". More than 20 failed logins in 5 minutes raise an alert in Slack (entry 61).
Production: at least 12 characters, a check against lists of leaked passwords, and a slowdown per account.

**Logout does not end the token (F7).**
A copied token keeps working until it expires, 6 hours after login.
Why accepted: the 6-hour limit bounds the damage.
Production: short tokens (minutes) with a refresh, and a way to revoke a token.

**Any discount and any dates are accepted (F16).**
A coupon can have a discount of 1000, or an end date before its start date.
Why accepted: it is a business rule, not an open door. Since #9, only logged-in staff can create coupons.
Production: discount between 0 and 100, end after start.

**CORS allows every website.**
CORS is the browser rule that says which other websites may call this API.
Why accepted: the login token travels in a header that the app's own code sets, not in a cookie that the browser adds by itself. So another website cannot act with a visitor's login.
Production: allow only the app's own address anyway.

**One database user for the three backends, and no record of who changed what.**
If one backend is taken over, it can change the other backends' data. The Gateway log shows which IP address called which path, but not which user changed which record.
Production: one database user per service, each limited to its own collections; an audit log of changes per user.

**Traffic inside the cluster is not encrypted.**
HTTPS ends at the Gateway. From there to the services and to MongoDB, traffic is plain.
Why accepted: network rules decide who may talk to whom inside the cluster (entry 25).
Production: a service mesh with mutual TLS, or Cilium's transparent encryption.

**The rate limits count per IP address, and their numbers are estimates.**
One machine is stopped; thousands of machines (a DDoS, a botnet) are not. The limits were set from estimates, not from a week of measured traffic (entry 27).
Production: Azure DDoS Protection or a web application firewall in front of the Gateway; limits first run in "dry run" mode, then set from what real users send.

**If Key Vault cannot be reached, the app keeps the last values.**
New secret values wait until Key Vault is back. Nothing stops.

**The MongoDB image has one known CRITICAL vulnerability.**
It is in Go version 1.24.6, which is built into the official MongoDB image (CVE-2025-68121). Go has fixed versions; a newer MongoDB image is on the plan (entry 64). The Trivy Operator scans the running image, and its alert reached Slack.

**Helm charts are pinned by version, not by digest.**
A version name could, in theory, be replaced with different content by the chart's publisher. The pipeline's own tools and actions are pinned by digest and commit hash (Part 9 of the build log); for the platform charts, a version pin is the accepted level.

---

## Demo shortcuts

These are choices made because the project ran for one week with one person. Each one would change in production.

- **One environment.** There is no staging: what is merged to `main` and approved goes to the only cluster.
- **MongoDB runs inside the cluster, as one pod, with no backups.** Production would use a managed database or a replica set with backups.
- **The HTTPS certificate is copied into Key Vault** and put back after a rebuild. Let's Encrypt gives only 5 certificates per week for the same name, and every rebuild would spend one. Only my account can read the copy.
- **The cluster is stopped at night** with `az aks stop` to save money. After a start, the backends restart until MongoDB is ready (entry 46).
- **After a full rebuild, the newest images are deployed by hand.** The manifests in git name an older image; one manual run of the pipeline on `main` fixes it (entry 32).
- **Cloudinary,** where menu images are stored, uses my own free account. Its keys are in Key Vault, and only `items` may read them.

---

## Known gaps

**In one line:** open, not accepted, and on the plan in the build log's [What is next](docs/build-log.md#what-is-next).

**Who may do what**

- **The cluster login is an admin certificate,** on my laptop and in the pipeline's deploy job. AKS is not connected to Entra ID, so `az aks get-credentials` gives full admin rights. With it, `kubectl port-forward` reaches any pod, MongoDB included, and network rules do not stop it (entry 54). The certificate stays valid for a long time: a copy would work until the cluster's certificates are replaced (entry 30). Production: Entra ID logins with multi-factor authentication, rights per namespace, admin rights only when needed.
- **Whoever takes over my GitHub account can approve deploys.** My accounts use multi-factor login, but the evidence does not show it.
- **Grafana has one shared local admin account,** with a strong password from Key Vault but no multi-factor login (#17).
- **Prometheus has no login.** It is not on the internet; it is reached only through `kubectl port-forward`, which needs the admin certificate above.
- **Some trusted controllers can read every Secret in the cluster:** cert-manager, External Secrets, and the Prometheus Operator (entries 15, 51).

**What gets built and what may run**

- **Images are pinned by digest but not signed.** A digest proves "these exact bytes"; a signature would also prove "built by our pipeline". Nothing in the cluster refuses an unsigned image.
- **An end-of-life base image passes the gate** as long as it has no CRITICAL vulnerability (entry 45).

**The network and the cluster's insides**

- **The `gateway`, `monitoring` and `trivy-system` namespaces have no network rules.** The app's namespace, `restauranty`, has them (#11).
- **`items` may reach any public address on HTTPS,** not only Cloudinary. Naming one website needs Cilium's FQDN rules, a paid AKS feature.
- **Trivy's scan jobs run as root,** on purpose, in their own namespace (entry 63).

**Seeing and responding**

- **Nobody can tell who read a secret in Key Vault.** Key Vault's diagnostic logs are not switched on.
- **Attacks that show only in the logs raise no alert.** For example, a request for the closed user list shows on the dashboard (entry 62), but no alert fires: Loki's rule engine is not connected to Alertmanager.
- **Nobody is on call.** An alert at night waits in Slack until morning.
- **No tested runbook for a leaked secret** (#16). The MongoDB password has not been rotated under load yet. Rotating the token signing key would log every user out.
- **The security headers are missing:** HSTS, Content-Security-Policy, X-Frame-Options and others, and the API still says `X-Powered-By: Express`. OWASP ZAP warns about them after every deploy (entry 42).

---

## Personal data (GDPR notes)

**In one line:** the app keeps a small amount of personal data, in one EU region; outside the database, copies live 7 days or less. Only fake test users exist.

**What the app stores about a user.** Email, first name, surname, address, phone number, role, and a bcrypt hash of the password. It is in MongoDB, on a disk in Azure's Germany West Central region. Azure encrypts managed disks at rest by default; this was not checked with a command.

**Where copies of it travel.**

- **The login token (F2, accepted above).** It holds the email, name, address and phone number, readable by whoever holds the token. It lives in the browser's local storage and expires after 6 hours.
- **The server logs: no longer.** The original code printed addresses and phone numbers into the log on every page load (F3). Those lines were removed (entry 6).
- **API answers: no password hashes.** No answer contains a hash any more (F11, F15), and the user list is closed at the Gateway (#10).

**Personal data in the monitoring.** The Gateway's access log records each visitor's IP address, the time, the path and the answer code. Under the GDPR, an IP address is personal data. These logs go to Loki, are shown only behind Grafana's login, and are deleted after 7 days. Prometheus metrics count requests by route and contain no personal data; they are also kept 7 days. Slack alerts carry only counts and a link to the dashboard, never IP addresses. Screenshots in this repository hide IP addresses.

**Who can read it.** The three backends, through one MongoDB user with rights on the app's database only. In the cluster: whoever holds the admin cluster login, which today is my laptop and the pipeline's deploy job (see Known gaps). Grafana's logs: whoever can log in to Grafana, which today is only me.

**Deleting a user.** Deleting the record in MongoDB removes it from the only place it is stored. There are no backups, so no old copies remain. A token issued before the deletion still works until it expires, at most 6 hours (F7). The user's IP address stays in the Gateway logs for up to 7 days.

**Outside the EU region.** Menu images go to Cloudinary, another company. They are photos of dishes, not personal data.
