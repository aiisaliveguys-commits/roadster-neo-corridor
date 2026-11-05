#!/usr/bin/env python3
"""Assert the built place file contains what the game needs to RUN, not just valid XML.

Why this exists: CI was green on a build where Rojo emitted every server file as a
ModuleScript. The XML parsed, the file opened in Studio, and no server code would
ever execute. A syntax gate cannot see that, because nothing is wrong with the
source text - the class mapping is wrong. So check the artifact, not the inputs.

Usage: python3 tools/check_place.py dist/roadster.rbxlx
"""
import re
import sys
import xml.etree.ElementTree as ET

EXPECT = {
    # service -> {class: [instance names]}
    "ServerScriptService": {"Script": ["main", "VehicleSpawner", "WantedService", "MissionService"]},
    "ReplicatedStorage": {
        "ModuleScript": ["Config", "CarController", "Remotes", "CityGenerator", "PlayerState"]
    },
    # searched transitively: Studio nests these under StarterPlayer > StarterPlayerScripts,
    # and a published place may clone the hierarchy, so "direct child of this service" is a
    # constraint that breaks for reasons that have nothing to do with the build being wrong
    "StarterPlayerScripts": {"LocalScript": ["Bootstrap", "HUD", "Radio"]},
}

# a name that survived Rojo's suffix stripping badly, e.g. "CityGenerator.module"
BAD_SUFFIX = re.compile(r"\.(module|server|client|init)$")


def subtree_names(node):
    """(class, name) for every descendant, used for transitive services."""
    out = []
    for item in node.findall("Item"):
        out.append((item.get("class"), identity(item)))
        out += subtree_names(item)
    return out


def identity(item):
    """Two XML dialects, both real:

      Rojo   <Item class="Script"><Properties><string name="Name">X</string>
      Studio <Item class="Script"><Properties><Property name="Name"><string>X</string>

    and service containers often carry no Name at all, where the class IS the
    identity. Reading only one dialect made this check report a good build as
    empty, which is the worst outcome a verification step can have: it teaches
    you to distrust it.
    """
    props = item.find("Properties")
    if props is not None:
        for path in ("string[@name='Name']", "Property[@name='Name']/string"):
            n = props.find(path)
            if n is not None and n.text:
                return n.text
    return item.get("class")


def collect(node, parent_name, out):
    for item in node.findall("Item"):
        name = identity(item)
        out.append((parent_name, item.get("class"), name, item))
        collect(item, name, out)


def main(argv):
    if len(argv) < 2:
        print("usage: check_place.py <file.rbxlx>")
        return 2
    path = argv[1]
    tree = ET.parse(path)
    root = tree.getroot()
    if root.tag != "roblox":
        print("FAIL: root element is %r, expected 'roblox'" % root.tag)
        return 1
    if root.get("version") != "4":
        print("FAIL: roblox version attr is %r, Studio expects 4" % root.get("version"))
        return 1

    out = []
    collect(root, None, out)

    problems = []
    for parent, cls, name, item in out:
        if name and BAD_SUFFIX.search(name):
            problems.append(
                "instance name %r still carries a Rojo suffix - requires for %r will hang"
                % (name, BAD_SUFFIX.sub("", name))
            )

    total_scripts = 0
    for service, want in EXPECT.items():
        found = dict((cls, set()) for cls in ("Script", "LocalScript", "ModuleScript"))
        descendants = set()
        for parent, cls, name, item in out:
            if name == service or cls == service:
                descendants |= set(subtree_names(item))
            elif parent == service:
                if name:
                    found.setdefault(cls, set()).add(name)
        # for the transitive case, fold in anything found inside the service subtree
        for cls, want_cls in list(want.items()):
            if not found.get(cls):
                found[cls] = {n for c, n in descendants if c == cls}
        for cls, names in want.items():
            have = found.get(cls, set())
            total_scripts += len(have) if cls != "ModuleScript" else 0
            missing = [n for n in names if n not in have]
            if missing:
                problems.append("%s/%s missing: %s" % (service, cls, ", ".join(missing)))
            else:
                print("  ok  %-20s %-12s %s" % (service, cls, ", ".join(names)))

    # The failure mode that started this: a place file whose only scripts are
    # ModuleScripts. Nothing errors, nothing runs.
    server_scripts = set()
    for parent, cls, name, _ in out:
        if cls == "Script" and parent == "ServerScriptService":
            server_scripts.add(name)
    if not server_scripts:
        problems.append(
            "no Script instances under ServerScriptService at all - the place would open "
            "and run no server logic (this is exactly the bug this check was written for)"
        )

    if problems:
        print("\nFAIL:")
        for p in problems:
            print("  - " + p)
        print("\n  (if you renamed a file, remember Rojo maps .server.lua -> Script, "
              ".client.lua -> LocalScript, .lua -> ModuleScript)")
        return 1

    parts = 0
    for _ in re.finditer(r'<Item class="Part"|<Item class="MeshPart"', open(path, "r", encoding="utf-8", errors="replace").read()):
        parts += 1
    print("\nPASS: place file has every expected script; %d baked Parts (city is runtime-generated, so ~0 is right)" % parts)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
