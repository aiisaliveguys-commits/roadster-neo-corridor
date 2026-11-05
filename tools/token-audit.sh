#!/usr/bin/env bash
# Audit what a GitHub token can actually touch. Read-only except one deliberate
# dry-probe: a POST with an intentionally invalid body, which GitHub rejects at
# field validation AFTER the scope check passes - so HTTP 422 proves the write
# scope is granted without creating anything.
#
#   GH_TOKEN=ghp_xxx bash tools/token-audit.sh
#
# Never commit a token. Never paste this output into a public issue.
set -uo pipefail
T="${GH_TOKEN:-}"
if [ -z "$T" ]; then
	echo "usage: GH_TOKEN=<token> $0" >&2
	exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
A=(-sS -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "=== identity ==="
curl "${A[@]}" https://api.github.com/user -o "$tmp/user.json"
python3 "$here/gh_parse.py" identity "$tmp/user.json"
login=$(python3 -c 'import json;print(json.load(open("'"$tmp"'/user.json")).get("login","me"))' 2>/dev/null || echo me)

echo
echo "=== granted scopes (the real answer) ==="
curl "${A[@]}" -D "$tmp/hdr.txt" -o /dev/null https://api.github.com/user
python3 "$here/gh_parse.py" scopes "$tmp/hdr.txt"

echo
echo "=== read probes ==="
probe() { printf "  %-22s HTTP %s\n" "$1" "$(curl "${A[@]}" -o /dev/null -w '%{http_code}' "$2")"; }
probe "private emails" "https://api.github.com/user/emails"
probe "ssh keys" "https://api.github.com/user/keys"
probe "gpg keys" "https://api.github.com/user/gpg_keys"
probe "org memberships" "https://api.github.com/user/memberships/orgs"
probe "gists (incl secret)" "https://api.github.com/gists"
probe "notifications" "https://api.github.com/notifications"

echo
echo "=== write probes (invalid body -> nothing is created) ==="
wkey=$(curl "${A[@]}" -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
	-d '{"key":"x"}' https://api.github.com/user/keys)
if [ "$wkey" = "422" ]; then
	echo "  !! CAN REGISTER AN SSH KEY (422 = scope granted, body rejected)"
	echo "     -> permanent account access survives deleting this token"
	echo "     -> if this is unexpected: revoke now, then check Settings/Keys"
else
	echo "  ssh-key write: HTTP $wkey (403 = not granted)"
fi

echo
echo "=== repository reach ==="
curl "${A[@]}" 'https://api.github.com/user/repos?per_page=100&affiliation=owner,collaborator,organization_member' -o "$tmp/repos.json"
python3 "$here/gh_parse.py" repos "$tmp/repos.json"

echo
echo "=== rate budget ==="
curl "${A[@]}" https://api.github.com/rate_limit |
	python3 -c 'import json,sys;d=json.load(sys.stdin).get("resources",{}).get("core",{});print("  core used=%s remaining=%s limit=%s"%(d.get("used"),d.get("remaining"),d.get("limit")))' 2>/dev/null
echo
echo "Surprised by any of the above?  https://github.com/settings/tokens"
