#!/usr/bin/env bash
# Security + hygiene audit, written for a PUBLIC repo whose CI is open to the world.
# Writes to $GITHUB_STEP_SUMMARY when present, stdout otherwise.
# Uses ONLY the CI-provided github.token, so a fork run can learn nothing secret -
# and it is not wired to pull_request at all, so forks cannot even reach it.

set -uo pipefail
S="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
fail=0
say() { printf '%s\n' "$1" >>"$S"; }

say "## Security audit"
say ""

# 1) repo visibility is a decision, not an accident - say it out loud every run
api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN:-}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}$1" 2>/dev/null; }

meta=$(api "")
if [ -n "$meta" ]; then
  vis=$(printf '%s' "$meta" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("visibility","?"))' 2>/dev/null || echo "?")
  say "- Repository visibility: **${vis}** (all committed content is world-readable)"
  [ "$vis" = "public" ] && say "  - therefore: no Roblox cookie, no \`.ROBLOSECURITY\`, no \`rbx-auth.json\`, no asset-upload token here. Ever. Not even as a secret."
fi

say ""
say "### Workflow trigger safety"
# A fork PR can only leak through a workflow that (a) runs with write/secrets in
# the BASE context and (b) echoes an attacker-controlled field. Bracketed dots
# below so this file does not match its own scan.
if grep -rnE 'pull_request[[:space:]]*:[[:space:]]*$|\bpull_request_target\b|workflow_run:' .github/workflows/*.yml >/dev/null 2>&1; then
  hit=$(grep -rnE '\bpull_request_target\b|workflow_run:' .github/workflows/*.yml 2>/dev/null | head -3 || true)
  if printf '%s' "$hit" | grep -q 'pull_request_target\|workflow_run'; then
    say "- **HIGH**: a dangerous trigger is present (fork code would run with base-repo secrets):"
    say '  ```'
    printf '%s\n' "$hit" >>"$S"
    say '  ```'
    fail=1
  else
    say "- ok: plain \`pull_request\` only (fork code runs with no secrets, read-only token)"
  fi
else
  say "- ok: plain \`pull_request\` only (fork code runs with no secrets, read-only token)"
fi

say ""
say "### Script-injection surface (untrusted input interpolated into shell)"
inj=$(grep -rnE '\$\{\{[[:space:]]*github[.]event[.](comment[.]body|issue[.]body|pull_request[.](title|body)|review[.]body|head[.]ref)' .github/workflows/*.yml 2>/dev/null || true)
if [ -n "$inj" ]; then
  say "- **HIGH**: event payload fields are being interpolated into a script:"
  say '  ```'
  printf '%s\n' "$inj" >>"$S"
  say '  ```'
  fail=1
else
  say "- ok: no \`github.event.*\` user text interpolated into \`run:\` blocks"
fi

say ""
say "### Least privilege"
for f in .github/workflows/*.yml; do
  top=$(grep -nE '^permissions:' "$f" | head -1 || true)
  if [ -z "$top" ]; then
    say "- **MED**: ${f} has no top-level \`permissions:\` (inherits repo default)"
    fail=1
  else
    say "- ok: ${f} declares an explicit top-level permissions block"
  fi
done

say ""
say "### Secret material accidentally committed"
leak=$(grep -rInE 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|x-oauth|-----BEGIN (RSA|OPEN)PRIVATE KEY|rbxcookie|ROBLOSECURITY' \
        --exclude-dir=.git . 2>/dev/null | grep -v 'security-audit.sh' | head -6 || true)
if [ -n "$leak" ]; then
  say "- **CRITICAL**: token/key shaped strings in the tree:"
  say '  ```'
  printf '%s\n' "$leak" >>"$S"
  say '  ```'
  fail=1
else
  say "- ok: no token/private-key shaped strings in the tree"
fi

say ""
say "### CI never pushes back"
if grep -rnE 'git push|actions/checkout@v[0-9]+.*token:[[:space:]]*[^G]' .github/workflows/*.yml >/dev/null 2>&1; then
  say "- **MED**: a workflow writes to git; on a public repo that is a supply-chain path"
  fail=1
else
  say "- ok: no \`git push\` from CI"
fi

say ""
say "### Roblox publishing path"
if [ -f .github/workflows/publish.yml ]; then
  say "- note: publish.yml exists - confirm it is trigger-gated to manual/dispatch only"
else
  say "- ok: no publish workflow, so no Roblox credential is expected in this repo"
  say "  - when you do want auto-publish, put that workflow in a **private** repo and"
  say "    pass the place file between repos as an artifact, or use Open Cloud API key"
  say "    (DataStore-only, revocable) instead of a login cookie"
fi

say ""
if [ "$fail" -ne 0 ]; then
  say "**Result: findings above need attention.**"
else
  say "**Result: clean.**"
fi

exit "$fail"
