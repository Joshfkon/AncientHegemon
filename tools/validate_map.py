#!/usr/bin/env python3
"""Sanity-check the HegemonCore map data. Usage: python3 tools/validate_map.py [path]"""
import json
import sys
from collections import defaultdict, deque
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "HegemonCore/Sources/HegemonCore/Resources/map.json"
TERRAINS = {"plains", "hills", "mountains", "forest", "desert"}
RESOURCES = {"grain", "copper", "tin", "horses", "timber", "gold"}
CROSSINGS = {"river", "strait"}
TAGS = {"river_valley", "barbarian_homeland"}


def main(path):
    data = json.loads(Path(path).read_text())
    errors = []
    terr = {t["id"]: t for t in data["territories"]}
    seas = {s["id"] for s in data["seas"]}

    if len(terr) != len(data["territories"]):
        errors.append("duplicate territory id")

    for t in terr.values():
        if t["terrain"] not in TERRAINS:
            errors.append(f"{t['id']}: unknown terrain {t['terrain']}")
        if not isinstance(t["grain"], int) or t["grain"] < 1:
            errors.append(f"{t['id']}: every territory needs grain >= 1")
        for r in t["resources"]:
            if r not in RESOURCES or r == "grain":
                errors.append(f"{t['id']}: bad resource {r}")
        for s in t["seas"]:
            if s not in seas:
                errors.append(f"{t['id']}: unknown sea {s}")
        for tag in t.get("tags", []):
            if tag not in TAGS:
                errors.append(f"{t['id']}: unknown tag {tag}")

    graph = defaultdict(set)
    seen = set()
    for link in data["landLinks"]:
        a, b = link[0], link[1]
        crossing = link[2] if len(link) > 2 else None
        for x in (a, b):
            if x not in terr:
                errors.append(f"landLink references unknown territory {x}")
        if crossing is not None and crossing not in CROSSINGS:
            errors.append(f"landLink {a}-{b}: unknown crossing {crossing}")
        key = frozenset((a, b))
        if key in seen:
            errors.append(f"duplicate landLink {a}-{b}")
        seen.add(key)
        graph[a].add(b)
        graph[b].add(a)

    for a, b in data["seaLinks"]:
        for x in (a, b):
            if x not in seas:
                errors.append(f"seaLink references unknown sea {x}")

    coast = defaultdict(set)
    for t in terr.values():
        for s in t["seas"]:
            coast[s].add(t["id"])
    for s in seas:
        if not coast[s]:
            errors.append(f"sea {s} has no coastal territory")

    for c in data["chokepoints"]:
        for t in c["heldBy"]:
            if t not in terr:
                errors.append(f"chokepoint {c['id']}: unknown territory {t}")
        link = c.get("gatesSeaLink")
        if link and sorted(link) not in [sorted(l) for l in data["seaLinks"]]:
            errors.append(f"chokepoint {c['id']}: gates a sea link that doesn't exist")

    for civ in data["civilizations"]:
        if civ["capital"] not in terr:
            errors.append(f"civ {civ['id']}: unknown capital")

    # Every territory must be reachable by land or by sea (islands via their coasts).
    sea_graph = defaultdict(set)
    for a, b in data["seaLinks"]:
        sea_graph[a].add(b)
        sea_graph[b].add(a)
    start = next(iter(terr))
    reached, queue = {start}, deque([start])
    while queue:
        n = queue.popleft()
        nbrs = set(graph[n]) if n in terr else set()
        if n in terr:
            nbrs |= set(terr[n]["seas"])
        else:
            nbrs |= sea_graph[n] | coast[n]
        for m in nbrs:
            if m not in reached:
                reached.add(m)
                queue.append(m)
    unreachable = (set(terr) | seas) - reached
    if unreachable:
        errors.append(f"unreachable: {sorted(unreachable)}")

    islands = sorted(t for t in terr if not graph[t])
    print(f"{len(terr)} territories, {len(data['landLinks'])} land links, "
          f"{len(seas)} seas, {len(data['chokepoints'])} chokepoints")
    print(f"islands (sea access only): {', '.join(islands)}")
    totals = defaultdict(int)
    for t in terr.values():
        totals["grain"] += t["grain"]
        for r, v in t["resources"].items():
            totals[r] += v
    print("map totals: " + ", ".join(f"{k} {v}" for k, v in sorted(totals.items())))

    if errors:
        print("\nERRORS:")
        for e in errors:
            print("  - " + e)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT))
