# Our DevSecOps approach

**What this is.** The idea and the method behind this project, in one place. The other two documents show the detail: the [security assessment](security-assessment.md) is what I found, the [build log](build-log.md) is what I built. This one is how I worked and why.

**How to read it.** Each section is short and stands on its own. Start with the story, then the method.

---

## The idea in one line

Take over an app, prove it is unsafe, then make it safe step by step — and at every step, follow a recognised standard instead of guessing.

## The story

The project follows one line from start to finish:

1. **The leak.** On day one, one request with no login returned every user's password hash and personal data.
2. **Contain.** Block the leak at the edge, fast, before fixing the code.
3. **Close.** Fix the code so the leak is gone at its source.
4. **Guard.** Make the pipeline test for it, so it cannot come back unnoticed.
5. **Detect.** If the attack is tried again, an alert fires.

Every part of the project fits somewhere on this line. It is also the order of a real incident: stop the bleeding, heal the wound, prevent the next one, watch for it.

## What "DevSecOps" means here

**Security is built into every step, not added at the end.** The older way was to build an app, then have a security team test it just before release. That is too late and too slow. DevSecOps puts a security check into each step instead:

| Step | The security built in |
| --- | --- |
| Writing code | A threat model decides what to check before code is written |
| Pull request | Review, secret scanning, dependency checks |
| Build | Scan the image for known vulnerabilities |
| Deploy | Secrets from a vault, least privilege, network rules |
| Run | Metrics, logs and alerts watch for attacks |

This is often called **shift left**: move the security checks earlier (to the left on a timeline), where problems are cheaper to fix.

## The standards we followed

Nothing here is invented for the project. Each part uses a public standard, so the work can be checked against something real:

| Area | Standard | How it is used |
| --- | --- | --- |
| Finding threats | **STRIDE** threat modelling, **trust boundaries** | Ask the six STRIDE questions at each boundary where trust changes |
| Naming risks | **OWASP Top 10 2025** | Every finding carries its category, e.g. A01 Broken Access Control |
| Testing | **OWASP WSTG** (Web Security Testing Guide) | Test the app step by step along its categories |
| What good looks like | **OWASP ASVS** | The target a fix aims for |
| Supply chain | **SLSA**, **SBOM**, provenance | Trace each image back to its code; scan what goes in |
| Access | **Least privilege**, **zero trust** | Each identity gets only its own rights; nothing is trusted for being "inside" |

## How we test

Testing follows one rule: **do not assume, prove it.** The method is the OWASP Web Security Testing Guide, worked through in nine steps (full detail in the [assessment](security-assessment.md)):

1. List every route the app has.
2. Use the app normally and watch what it sends back.
3. Test login and the token.
4. Test permissions: every route with no token, a broken token, a forged token.
5. Check every answer for data that should not be there.
6. Send unexpected input and abuse business rules.
7. Check errors, logs and behaviour under load.
8. Run tools (Trivy, Semgrep, gitleaks) to catch what people miss.
9. Report: a decision for every finding.

**White box.** I had the source code, so I read it to know where to look, then confirmed each suspicion with a real request. A suspicion becomes a finding only when a request proves it.

**Tools and people together.** The tools found none of the logic findings (an open route, a public secret): those need understanding of what the app should do. A tool (gitleaks) found a leaked key that manual review missed. Neither alone is enough.

## How we decide on each finding

Finding a problem is not the same as fixing everything at once. Each finding gets one honest decision:

| Decision | Meaning |
| --- | --- |
| **Fix** | Change the code so the problem is gone at its source |
| **Contain** | Block it outside the app (at the Gateway) as a fast first layer |
| **Detect** | An alert tells us when it happens |
| **Accept** | Not fixed this week, on purpose, with the reason written down |
| **Report** | The problem belongs to someone else; tell them, do not touch it |

Writing "Accept" with a reason is a real decision, not a gap. It shows what was chosen and why, under real time limits.

## Defence in depth

No single wall is trusted. The same threat is met by several independent measures, so if one fails the others still hold. Security people group them in three:

| Kind | Example in this project |
| --- | --- |
| **Prevent** | Fix the code; block the route at the Gateway; network rules; secrets in a vault |
| **Detect** | Metrics, logs in Loki, alerts on attacks |
| **Respond** | A runbook to rotate a leaked secret |

The worst finding, the leaked user list, is met four ways: the route is blocked at the edge, the code no longer returns the hash, the pipeline tests for it, and an alert watches for it.

## How we work

The way the work is organised is part of the method:

- **Every change starts with an issue.** The open issues are the plan.
- **Branches and pull requests.** No change goes straight to `main`; each is reviewed and can be undone on its own.
- **Conventional Commits.** Each commit says what kind of change it is and why.
- **Evidence, not claims.** Each fix is retested with the same attack that proved the problem, and the before and after are saved.
- **Everything is written down.** Three documents (assessment, build log, this one) and the issues link each claim to its proof.

The exact rules (branch names, commit format, the test checklist before a pull request) are in [CONTRIBUTING.md](../CONTRIBUTING.md). `.gitmessage` is the commit template: with `git config commit.template .gitmessage`, every new commit message starts from it.

## What we accepted, and what production would add

The project is honest about its limits. Some things are left for a reason and named as such:

- The app signs its own tokens. Production would use an identity provider (Entra External ID, Keycloak) that holds the keys and rotates them.
- The monitoring stack has no login between its parts; network rules are the only control. Production would authenticate every hop.
- Some demo shortcuts (every new user is an admin) are documented, not fixed.

Naming these is part of the approach: a real assessment says what it did **and** what it did not do, and why.

## The three documents

| Document | Question it answers |
| --- | --- |
| [security-assessment.md](security-assessment.md) | What is wrong, and how do I know? |
| [build-log.md](build-log.md) | What did I build to fix it? |
| This one | How did I work, and why that way? |
