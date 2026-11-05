#!/usr/bin/env python3
"""Parse GitHub API responses for tools/token-audit.sh. Read-only, no network."""
import json
import sys


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def scopes(argv):
    hdr = {}
    try:
        with open(argv[0], "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" in line:
                    k, v = line.split(":", 1)
                    hdr[k.strip().lower()] = v.strip()
    except Exception:
        pass
    granted = hdr.get("x-oauth-scopes")
    print("  raw header   : %s" % (granted if granted is not None else "(absent)"))
    if not granted:
        print("  parsed       : (none) -> fine-grained PAT; read its per-repo grants, not scopes")
        return 0
    names = sorted(s.strip() for s in granted.split(",") if s.strip())
    print("  parsed       : %d scope(s)" % len(names))
    for n in names:
        print("    - %s" % n)
    danger = {
        "admin:public_key": "can register an SSH key -> permanent access even after this token is deleted",
        "admin:repo_hook": "can install a webhook -> exfiltrate every event, forever",
        "workflow": "can rewrite Actions workflows -> code execution on runners with their secrets",
        "repo": "full read/write of every repo incl. private",
        "delete:packages": "can destroy published packages",
        "admin:org": "org-level admin",
        "user": "profile incl. private/verified email",
        "notifications": "reads notification bodies (can contain tokens people pasted)",
    }
    risky = [n for n in names if n in danger]
    if risky:
        print("\n  high-impact scopes present:")
        for n in risky:
            print("    !! %-18s %s" % (n, danger[n]))
    else:
        print("\n  no high-impact scopes; reasonable blast radius")
    return 0


def identity(argv):
    d = load(argv[0]) or {}
    for k in ("login", "id", "type", "site_admin", "created_at", "public_repos"):
        print("  %-13s %s" % (k, d.get(k)))
    plan = d.get("plan") or {}
    print("  %-13s %s" % ("plan", plan.get("name")))
    if d.get("site_admin"):
        print("  !! site_admin is True on this account")
    return 0


def repos(argv):
    rs = load(argv[0])
    if not isinstance(rs, list):
        print("  (no repo list: %s)" % (rs if rs else "unreadable"))
        return 0
    adm = sum(1 for r in rs if (r.get("permissions") or {}).get("admin"))
    wr = sum(1 for r in rs if (r.get("permissions") or {}).get("push") and not (r.get("permissions") or {}).get("admin"))
    pv = sum(1 for r in rs if r.get("private"))
    wf = sum(1 for r in rs if r.get("has_workflows"))
    print("  visible=%d admin=%d write=%d private=%d with-workflows=%d" % (len(rs), adm, wr, pv, wf))
    for r in rs[:12]:
        p = r.get("permissions") or {}
        role = "admin" if p.get("admin") else ("write" if p.get("push") else "read")
        print("    %-42s [%s]%s" % (r.get("full_name"), role, "  PRIVATE" if r.get("private") else ""))
    if len(rs) > 12:
        print("    ... +%d more" % (len(rs) - 12))
    if wf:
        print("  note: %d repo(s) have Actions enabled - combined with `workflow` scope that is" % wf)
        print("        runner code execution + access to that repo's secrets"  )
    return 0


def main():
    if len(sys.argv) < 2:
        print("usage: gh_parse.py identity|scopes|repos <file>")
        return 2
    fn = {"identity": identity, "scopes": scopes, "repos": repos}.get(sys.argv[1])
    if fn is None:
        print("unknown mode")
        return 2
    return fn(sys.argv[2:])


if __name__ == "__main__":
	sys.exit(main())
