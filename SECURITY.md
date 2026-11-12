# Security policy

**What this is.** How to report a security problem, what is accepted on purpose, what was simplified for the demo, which known gaps are still open, and what personal data the app keeps. The reasoning behind each point is in the [threat model](docs/threat-model.md); the proof is in the [build log](docs/build-log.md) and the [security assessment](docs/security-assessment.md).

**State:** 12 November 2026.

---

## Reporting a problem

**Please report privately, not in a public issue.** On GitHub, open the **Security** tab of this repository and choose **Report a vulnerability**. Only I can read the report. Describe what you did, what happened, and what you expected.

This is a bootcamp project run by one person, so there is no fixed answer time. I aim to reply within a week.

**Why the findings in this repository are public.** The [security assessment](docs/security-assessment.md) describes the app as I received it from the course, with fake users on my laptop. The problems in it are fixed, contained or accepted below, and the original code is public anyway. A new problem in the deployed system is different: report it privately first.

---

## Accepted on purpose

Each of these is known, tested, and not fixed this week. For each: what it is, why it is accepted, and what a production system would do. The IDs (F1 to F20) are the findings of the [security assessment](docs/security-assessment.md#step-9-report).

**Every new account is an admin (F1).**
Why accepted: the frontend is a back office for restaurant staff, and its pages only show for admins. Without this shortcut, nobody could use the demo.
Production: new accounts start as normal users; admins are set up separately.

**Personal data inside the login token (F2).**
A login token is only encoded, not encrypted. Anyone who holds a token can read the email, name, address and phone number in it.
Why accepted: the profile page reads these fields from the token.
Production: the token carries only the user's id and role; the profile page asks the server.

**Weak passwords are accepted (F5).**
`Password1` is allowed.
Why accepted: the two ways to guess passwords are closed or slowed. Offline guessing needs the password hashes, and no answer contains them any more. Online guessing is limited at the Gateway: each IP address gets 10 logins per minute, after that the answer is 429 "too many requests". Many failed logins raise an alert in Slack.
Production: at least 12 characters, and a check against lists of leaked passwords.

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
Why accepted: network rules decide who may talk to whom inside the cluster (story 11 in the threat model).
Production: a service mesh with mutual TLS, or Cilium's transparent encryption.

**No protection against large floods from many addresses (DDoS).**
The Gateway limits each IP address, which stops one machine, not thousands.
Production: Azure DDoS Protection or a web application firewall in front of the Gateway.

**If Key Vault cannot be reached, the app keeps the last values.**
New secret values wait until Key Vault is back. Nothing stops.

**The MongoDB image has one known CRITICAL vulnerability.**
It is in Go version 1.24.6, which is built into the official MongoDB image (CVE-2025-68121). Go has fixed versions; a newer MongoDB image is on the plan ([build log, entry 64](docs/build-log.md#64-the-scanner-checked-three-corrections-in-one-evening)). Trivy Operator scans the running image and the alert is in Slack.

---

## Demo shortcuts

These are choices made because the project ran for one week with one person. Each one would change in production.

- **One environment.** There is no staging: what is merged to `main` and approved goes to the only cluster.
- **MongoDB runs inside the cluster, as one pod, with no backups.** Production would use a managed database or a replica set with backups.
- **The HTTPS certificate is copied into Key Vault** and put back after a rebuild. Let's Encrypt gives only 5 certificates per week for the same name, and a rebuild would otherwise spend one each time.
- **The cluster is stopped at night** with `az aks stop` to save money. After a start, the backends restart until MongoDB is ready (entry 46).
- **Cloudinary,** where menu images are stored, uses my own free account. Its keys are in Key Vault, and only `items` may read them.

---

## Known gaps

These are open, not accepted. Each is on the plan in the build log's [What is next](docs/build-log.md#what-is-next).

- **Nobody can tell who read a secret in Key Vault.** Key Vault's diagnostic logs are not switched on.
- **The cluster login is an admin certificate,** on my laptop and in the pipeline's deploy job. AKS is not connected to Entra ID, so `az aks get-credentials` gives admin rights. With it, `kubectl port-forward` reaches any pod, MongoDB included, and network rules do not stop it (entry 54). Production: Entra ID logins with multi-factor authentication, and admin rights only when needed.
- **Grafana has one shared local admin account,** with a strong password from Key Vault but no multi-factor login (#17).
- **Images are pinned by digest but not signed.** A digest proves "these exact bytes"; a signature would also prove "built by our pipeline".
- **Some trusted controllers can read every Secret in the cluster:** cert-manager, External Secrets and the Prometheus Operator (entries 15, 51).
- **The `gateway` and `monitoring` namespaces have no network rules yet.** The app namespace, `restauranty`, has them (#11).

---

## Personal data (GDPR notes)

**In one line:** the app keeps a small amount of personal data, in one EU region, mostly for 7 days or less outside the database. Only fake test users exist.

**What the app stores about a user.** Email, first name, surname, address, phone number, role, and a bcrypt hash of the password. It is in MongoDB, on a disk in Azure's Germany West Central region. Azure encrypts managed disks at rest by default; this was not checked with a command.

**Where copies of it travel.**

- **The login token (F2, accepted above).** It holds the email, name, address and phone number, readable by whoever holds the token. It lives in the browser's local storage and expires after 6 hours.
- **The server logs: no longer.** The original code printed addresses and phone numbers into the log on every page load (F3). Those lines were removed (#21).
- **API answers: no password hashes.** No answer contains a hash any more (F11, F15, #21), and the full user list is closed at the Gateway (#10).

**Personal data in the monitoring.** The Gateway's access log records the visitor's IP address, the time, the path and the answer code. Under GDPR, an IP address is personal data. These logs go to Loki and are deleted after 7 days. Prometheus metrics count requests by route and contain no personal data; they are also kept 7 days.

**Who can read it.** The three backends, through one MongoDB user with rights on the app's database only. In the cluster: whoever holds an admin cluster login, which today is only me and the pipeline's deploy job (see Known gaps). Grafana's logs: whoever can log in to Grafana, which today is only me.

**Deleting a user.** Deleting the record in MongoDB removes it from the only place it is stored. There are no backups, so no old copies remain. A token issued before the deletion still works until it expires, at most 6 hours (F7). The user's IP address stays in the Gateway logs for up to 7 days.

**Outside the EU region.** Menu images go to Cloudinary, another company. They are photos of dishes, not personal data. Slack alerts carry counts and names of services, not users' data.
