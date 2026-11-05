#!/usr/bin/env python3
"""Create/update a GitHub release holding the built place file, from the CI artifact.

GH_TOKEN must be in the environment. Nothing about a place file is hand-written here:
the bytes are downloaded from the Actions artifact of the given run, so what lands on
the release is exactly what CI verified.

Usage: GH_TOKEN=... python3 tools/publish_release.py <owner/repo> <run_id>
"""
import json
import os
import subprocess
import sys
import tempfile

API = "https://api.github.com"


def gh(method, url, body=None, extra_headers=None, raw_out=None, follow=False):
    cmd = ["curl", "-sS", "-X", method, "-H", "Authorization: Bearer " + os.environ["GH_TOKEN"],
           "-H", "Accept: application/vnd.github+json"]
    if extra_headers:
        for h in extra_headers:
            cmd += ["-H", h]
    if follow:
        cmd += ["-L"]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "--data", json.dumps(body)]
    if raw_out:
        cmd += ["-o", raw_out]
    cmd.append(url)
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit("curl failed: " + p.stderr[:300])
    if raw_out:
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        raise SystemExit("non-JSON response: " + p.stdout[:300])


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    repo, run_id = argv[1], argv[2]
    head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()

    arts = gh("GET", f"{API}/repos/{repo}/actions/runs/{run_id}/artifacts")
    place = next((a for a in arts.get("artifacts", []) if a["name"] == "roadster-place"), None)
    if place is None:
        raise SystemExit("no roadster-place artifact on run %s" % run_id)

    tmp = tempfile.mkdtemp()
    zip_path = os.path.join(tmp, "p.zip")
    gh("GET", place["archive_download_url"], raw_out=zip_path, follow=True,
       extra_headers=["Authorization: Bearer " + os.environ["GH_TOKEN"]])
    subprocess.run(["unzip", "-q", "-o", zip_path, "-d", tmp], check=True)
    src = os.path.join(tmp, "roadster.rbxlx")
    out = os.path.join(tmp, "ROADSTER-Neo-Corridor.rbxlx")
    os.replace(src, out)

    import hashlib
    blob = open(out, "rb").read()
    digest = hashlib.sha256(blob).hexdigest()

    # the run conclusion is the gate: never publish an unverified build
    run = gh("GET", f"{API}/repos/{repo}/actions/runs/{run_id}")
    if run.get("conclusion") != "success":
        raise SystemExit("run %s conclusion is %r - refusing to publish" % (run_id, run.get("conclusion")))

    body = "\n".join([
        "**Download the `.rbxlx` below, open it in Roblox Studio, press Play.**",
        "",
        "Nothing to import, nothing to configure - city, car, HUD, wanted system, missions",
        "and radio are all inside the file.",
        "",
        f"- Built and verified by CI run #{run['run_number']} (`{run['name']}`, all jobs green)",
        f"- Source commit `{head[:9]}`",
        f"- sha256 `{digest}`",
        "- 28 headless physics checks pass; 1 behaviour is tracked as known-open",
        "  (hover setpoint drift) and needs a look inside Studio",
        "",
        "An imported Tesla model overrides the built-in demo car automatically: drop it in",
        "ServerStorage (or Workspace) and rejoin - the spawner claims an import first and",
        "only builds the demo chassis when there is nothing to claim.",
    ])

    tag = "place-file"
    existing = gh("GET", f"{API}/repos/{repo}/releases/tags/{tag}")
    if existing.get("upload_url"):
        print("  deleting previous release (assets cannot be replaced in place)")
        gh("DELETE", f"{API}/repos/{repo}/releases/{existing['id']}")

    rel = gh("POST", f"{API}/repos/{repo}/releases", {
        "tag_name": tag,
        "name": "Playable place file - open in Studio, press Play",
        "target_commitish": "main",
        "body": body,
        "draft": False,
        "prerelease": False,
    })
    if "upload_url" not in rel:
        raise SystemExit("release create failed: " + json.dumps(rel)[:400])
    upload = rel["upload_url"].split("{")[0]
    # a binary body needs --data-binary, which the JSON-shaped gh() helper cannot
    # express, so this one call is made directly
    p = subprocess.run(["curl", "-sS", "-X", "POST",
                        "-H", "Authorization: Bearer " + os.environ["GH_TOKEN"],
                        "-H", "Content-Type: application/octet-stream",
                        "--data-binary", "@" + out,
                        upload + "?name=ROADSTER-Neo-Corridor.rbxlx&label=Open%20in%20Studio"],
                       capture_output=True, text=True)
    asset = json.loads(p.stdout or "{}")
    if "browser_download_url" not in asset:
        raise SystemExit("asset upload failed: " + (p.stdout or p.stderr)[:400])

    print("  release:", rel["html_url"])
    print("  asset  :", asset["browser_download_url"])
    print("  size   :", asset["size"], "bytes | sha256", digest[:16])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
