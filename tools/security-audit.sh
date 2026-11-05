#!/usr/bin/env bash
# Security + hygiene audit, written for a PUBLIC repo whose CI is open to the world.
# Writes to $GITHUB_STEP_SUMMARY when present, stdout otherwise.
# Uses ONLY the CI-provided github.token, so a fork run can learn nothing secret -
# and it is not wired to pull_request at all, so forks cannot even reach it.

set -uo pipefail
S="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
fail=0
say() { printf '%s\n' "$1" >>"$S"; }
block() { say '  ```'; printf '%s\n' "$1" >>"$S"; say '  ```'; }

say "## Security audit"
say ""

api() {
	curl -sS -H "Authorization: Bearer ${GH_TOKEN:-}" -H "Accept: application/vnd.github+json" \
		"https://api.github.com/repos/${GITHUB_REPOSITORY:-owner/repo}$1" 2>/dev/null
}

# 1) repo visibility is a decision, not an accident - say it out loud every run
vis=$(api "" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("visibility", "?"))
except Exception:
    print("?")' 2>/dev/null || echo "?")
say "- Repository visibility: **${vis}**"
if [ "$vis" = "public" ]; then
	say "  - all committed content is world-readable, so: no Roblox cookie, no \`.ROBLOSECURITY\`,"
	say "    no \`rbx-auth.json\`, no asset-upload token here. Ever. Not even as a secret."
fi

say ""
say "### Workflow trigger safety"
# Scan YAML STRUCTURE, not prose. This replaced two false alarms: a comment that
# merely names pull_request_target ("... is never used") scored as HIGH, and an
# `on: [pull_request]` flow-array parsed as a `pull_request:` key. Trigger keys are
# only read where they can actually be keys.
trig=$(awk '/^[[:space:]]*on:/{on=1; print FILENAME" line "NR": "$0; next}
            on && /^[^[:space:]#]/{on=0}
            on && /^[[:space:]]+[a-zA-Z_]/{print FILENAME" line "NR": "$0}' \
	.github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)
danger=$(printf '%s\n' "$trig" | grep -iE 'pull_request_target|workflow_run|repository_dispatch' | head -3 || true)
if [ -n "$danger" ]; then
	say "- **HIGH**: a dangerous trigger is present (fork code would run with base-repo secrets):"
	block "$danger"
	fail=1
else
	say "- ok: no privileged fork trigger in any \`on:\` block"
	printf 'Triggers found:\n%s\n' "$trig" | sed 's/^/  /' >>"$S"
fi

say ""
say "### Script-injection surface (untrusted input interpolated into shell)"
# Comment lines are dropped: prose *about* injection is not injection.
inj=$(grep -hnF '${{' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null |
	sed 's/^[[:space:]]*//' | grep -vE '^#' |
	grep -E 'github\.event\.(comment\.body|issue\.body|pull_request\.(title|body)|review\.body|head\.ref)' |
	head -3 || true)
if [ -n "$inj" ]; then
	say "- **HIGH**: event payload fields are interpolated straight into a script:"
	block "$inj"
	fail=1
else
	say "- ok: no \`github.event.*\` user text interpolated into a \`run:\` block"
fi

say ""
say "### Least privilege"
wrote=0
for f in $(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null); do
	wrote=1
	if grep -qE '^permissions:' "$f" 2>/dev/null; then
		say "- ok: ${f} declares an explicit top-level permissions block"
	else
		say "- **MED**: ${f} has no top-level \`permissions:\` (inherits the repo default)"
		fail=1
	fi
done
[ "$wrote" = 1 ] || say "- (no workflow files found)"
say ""
say "### Secret material accidentally committed"
# Two passes, because they catch different mistakes.
#
# Pass 1 - credential NAMES. Anything here is a leak by definition: no legitimate
# file in this repo needs to spell ROBLOSECURITY. (A broad "value-shaped" regex
# alone misses it, since a Roblox cookie is `_2|YmFzZQ...` and has no fixed prefix.)
# tools/ and this file are excluded: they ship audit code that must name the thing
# it hunts, and scanning them produces nothing but noise.
namehits=$(grep -rInE 'ROBLOSECURITY|rbx-auth\.json|\.ROBLOSECURITY|x-access-token' \
	--exclude-dir=.git --exclude-dir=tools --exclude=security-audit.sh --exclude=.gitignore --exclude=.gitattributes . 2>/dev/null | head -4 || true)
#
# Pass 2 - credential SHAPES, only when bound to a key. A bare mention of a scope
# header name (gh_parse.py reads x-oauth-scopes) is not a secret; `TOKEN=ghp_...` is.
shapehits=$(grep -rInE '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|[A-Z_]{6,}(TOKEN|KEY|SECRET|COOKIE)[[:space:]]*=[[:space:]]*["'"'"']?[A-Za-z0-9_|.:+/-]{16,})' \
	--exclude-dir=.git --exclude-dir=tools --exclude=security-audit.sh --exclude=.gitignore --exclude=.gitattributes . 2>/dev/null | head -4 || true)
leak=$(printf '%s\n%s\n' "$namehits" "$shapehits" | grep -v '^$' | sort -u | head -8 || true)
if [ -n "$leak" ]; then
	say "- **CRITICAL**: credential material in the tree:"
	block "$leak"
	fail=1
else
	say "- ok: no credential names or token-shaped values in the tree"
fi

say ""
say "### CI never pushes back"
if grep -rqE '\bgit push\b' .github/workflows/ 2>/dev/null; then
	say "- **MED**: a workflow writes to git; on a public repo that is a supply-chain path"
	fail=1
else
	say "- ok: no \`git push\` from CI"
fi

say ""
say "### Roblox publishing path"
if [ -f .github/workflows/publish.yml ]; then
	say "- note: publish.yml exists - confirm it is gated to workflow_dispatch only"
else
	say "- ok: no publish workflow, so no Roblox credential is expected in this repo"
	say "  - when auto-publish is wanted: put that job in a **private** repo and hand it"
	say "    the place file as an artifact, or use a revocable Open Cloud API key rather"
	say "    than a \`.ROBLOSECURITY\` login cookie"
fi

say ""
if [ "$fail" -ne 0 ]; then
	say "**Result: findings above need attention (see ${fail} group(s)).**"
else
	say "**Result: clean.**"
fi

exit "$fail"
