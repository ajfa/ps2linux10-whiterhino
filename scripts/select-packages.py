#!/usr/bin/env python3
"""List the RPM files the Sony installer puts on disk for "WindowMaker Workstation".

Reads base/comps from a mounted DISC 2 (Base + the group, sub-groups, conditional
blocks and the mips architecture filter) and prints one RPM file name per line.

Usage: select-packages.py /path/to/mounted/DISC2 > config/packages.txt
"""
import os
import re
import subprocess
import sys

disc = sys.argv[1]
rpms = os.path.join(disc, "SCEI", "RPMS")
comps = open(os.path.join(disc, "SCEI", "base", "comps"), encoding="latin-1").read().splitlines()

groups, cond, cur, ccur = {}, {}, None, None
for line in comps:
    s = line.strip()
    m = re.match(r"^[01] (?:--hide )?(.+?) \{$", line)
    if m:
        cur = m.group(1)
        groups[cur] = []
        continue
    m = re.match(r"^\? (.+?) \{$", s)
    if m and cur:
        ccur = m.group(1)
        cond.setdefault(cur, []).append((ccur, []))
        continue
    if s == "}":
        if ccur:
            ccur = None
        else:
            cur = None
        continue
    if cur and s:
        (cond[cur][-1][1] if ccur else groups[cur]).append(s)


def arch_ok(entry):
    m = re.match(r"^(!?)([a-z0-9]+): (.+)$", entry)
    if not m:
        return entry
    neg, arch, name = m.groups()
    if neg:
        return None if arch == "mips" else name
    return name if arch == "mips" else None


def expand(group, seen):
    out = set()
    for e in groups[group]:
        e = arch_ok(e)
        if e is None:
            continue
        if e.startswith("@ "):
            sub = e[2:]
            if sub not in seen:
                seen.add(sub)
                out |= expand(sub, seen)
        else:
            out.add(e)
    return out


seen = {"Base", "WindowMaker Workstation"}
want = expand("Base", seen) | expand("WindowMaker Workstation", seen)
for g in list(seen):
    for c, entries in cond.get(g, []):
        if c in seen:
            for e in entries:
                e = arch_ok(e)
                if e and not e.startswith("@ "):
                    want.add(e)

byname = {}
for f in sorted(os.listdir(rpms)):
    if f.endswith(".rpm"):
        name = subprocess.run(["rpm", "-qp", "--nosignature", "--qf", "%{NAME}", os.path.join(rpms, f)],
                              capture_output=True, text=True, errors="replace").stdout.strip()
        byname[name] = f
missing = sorted(w for w in want if w not in byname)
if missing:
    print("not on the disc: " + " ".join(missing), file=sys.stderr)
print("\n".join(sorted(byname[w] for w in want if w in byname)))
