# Contributing

How work is planned, branched, committed and merged in this repository.

## Workflow

1. Every change starts with an issue. The open issues are the plan.
2. Create a branch from an up-to-date `main` (names below).
3. Make small commits, one logical change each (format below).
4. Test before opening a pull request (checklist below).
5. Open a pull request to `main` with `Closes #<number>` in the description.
   Merging closes the issue.

`main` must always work.

### Committing straight to `main`

Allowed only for changes that can't break anything that runs:

- `docs`: README, SECURITY.md, the threat model, this guide, results, typos
- `chore`: `.gitignore`, renames of files nothing refers to

Everything else goes through an issue and a pull request: app code,
Dockerfiles, Terraform, manifests, the pipeline and test scripts. If you're
unsure, it's not a direct commit.

`main` is protected (pull requests required). Direct `docs` and `chore`
commits work because the repository admin may bypass the rule; nobody else
can.

## Issues and labels

There is no project board. Every issue gets exactly one label:

| Label | Meaning |
| --- | --- |
| `baseline` | Required by the project brief |
| `devsecops` | My security layer on top: findings, hardening, gates, alerts |

The README links each claim to its issue and pull request, so the label
keeps the brief's deliverables apart from my own findings.

Create the labels once:

```bash
gh label create baseline  --color 0E8A16 --description "Required by the project brief"
gh label create devsecops --color B60205 --description "Security layer beyond the brief"
```

## Branch names

`<issue number>-<short-topic>`, lower case, words joined by hyphens:

| Branch | Issue |
| --- | --- |
| `4-rs256-signing` | #4 Switch JWT signing to RS256 |
| `7-gateway-https` | #7 Manifests, MongoDB, Gateway routing, HTTPS |
| `21-hide-password-hashes` | #21 Never return password hashes |

```bash
git switch main && git pull
git switch -c 4-rs256-signing
# ... commits ...
git push -u origin 4-rs256-signing
gh pr create --fill --body "Closes #4"
gh pr merge --merge --delete-branch
git switch main && git pull
```

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`

- **description:** imperative ("add", not "added"), lower case, under 72
  characters, no period. Test: "If applied, this commit will
  *add rate limit to login*" must read naturally.
- **body (optional):** why the change was made, wrapped at 72 characters.
- **footer:** `Closes #<number>` when the commit finishes an issue.

### Type: what kind of change?

| Type | Use it when | Ask yourself | Example |
| --- | --- | --- | --- |
| `feat` | The app or platform can do something new | "Can a user or operator see or use something new?" | `feat(k8s): route /api paths through the gateway` |
| `fix` | Something was wrong or insecure and now isn't | "Was this a bug or a finding?" | `fix(auth): never return password hashes` |
| `refactor` | Cleaner code, exactly the same behavior | "Would anyone notice a difference? No → refactor" | `refactor(items): move jwt options into config` |
| `perf` | Same behavior, faster or lighter | "Is the only goal speed or resources?" | `perf(client): serve the build with nginx` |
| `docs` | Only text for humans | "Does no code or config change?" | `docs: add stride tables to threat model` |
| `test` | Tests, attack scripts, k6, curl checks | "Does it only check things?" | `test: add k6 password-guessing script` |
| `build` | What goes into an image: Dockerfiles, dependencies | "Does it change an image?" | `build(auth): run as non-root with node server.js` |
| `ci` | GitHub Actions workflows | "Does it change what runs on GitHub?" | `ci: block on critical trivy findings` |
| `chore` | Housekeeping, no behavior change | "Is it tidying?" | `chore: ignore terraform state and key files` |

### Scope: which part of the project?

The scope is the folder or component you changed. Leave it out when the
change spans the whole project: `docs: add contributing guide`.

| Scope | Covers |
| --- | --- |
| `auth`, `discounts`, `items` | `backend/<service>/`: code, Dockerfile, package files |
| `client` | `client/`: the React frontend and its Dockerfile |
| `compose` | local dev: `docker-compose.yml`, `haproxy.cfg` |
| `terraform` | `terraform/`: persistent layer and cluster |
| `k8s` | `k8s/`: manifests, Gateway, NetworkPolicies, External Secrets |
| `monitoring` | Prometheus, Grafana, Loki, Alloy, alert rules, Falco |

`ci` and `docs` are types, not scopes: `ci: add zap baseline scan`.

### Tricky cases

| Situation | Pick | Why |
| --- | --- | --- |
| Closing a security finding in app code | `fix(<service>)` | It was wrong behavior, even if nobody reported it |
| Adding a NetworkPolicy or Gateway rule | `feat(k8s)` | The platform gains a new control |
| Hardening a Dockerfile (non-root, smaller base) | `build(<service>)` | It changes what goes into the image |
| Adding a security gate to the pipeline | `ci` | It changes what runs on GitHub |
| Saving "before" curl output to docs | `docs` | Evidence is text for humans |
| A change touching two services the same way | `fix: ...` (no scope) | Or split it into one commit per service |

If two types still seem right, the commit probably does two things: split it.

### Commit template

The template is in the repository as `.gitmessage`. Turn it on once per
clone, from the project folder:

```bash
git config commit.template .gitmessage
git config core.editor nano
```

Then commit with `git commit` (without `-m`). Lines starting with `#` are
hints and are left out of the message.

## Testing before a pull request

Check what your change can affect:

- **App code:** the service starts locally and login still works end to end
  (sign up, log in, create an item).
- **Dockerfiles:** the image builds and the container starts as non-root.
- **Terraform:** `terraform fmt -check` and `terraform validate` pass; read
  the `plan` before `apply`.
- **Manifests:** `kubectl apply` succeeds and all pods are `Running` and ready.
- **Security:** the curl security tests pass (`/api/auth/users` blocked,
  writes without a token get 401, no `password` field in any response).

## Secrets

Never commit passwords, keys, `.env` files, JWT key pairs (`*.pem`),
`*.tfvars`, Terraform state, kubeconfig files, or Kubernetes Secret
manifests with real values. Secret values go to Key Vault with
`az keyvault secret set`, nowhere else. `.gitignore` blocks the usual ones.

A secret that was pushed once stays in the history: rotate the secret, don't
just delete the file.
