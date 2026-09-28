#!/usr/bin/env python3
"""Render a release formula to stdout from an exact downloaded GitHub source archive."""
import hashlib
from pathlib import Path
import re
import sys
import tarfile

if len(sys.argv) != 3 or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", sys.argv[1]):
    raise SystemExit("Usage: render-homebrew-formula.py vX.Y.Z downloaded-source.tar.gz")

tag, archive = sys.argv[1], Path(sys.argv[2])
version = tag[1:]
# Inspect, never extract, and reject the wrong version/source before publishing a formula.
with tarfile.open(archive, "r:gz") as source:
    member = source.getmember(f"contactctl-{version}/Sources/contactctl/ContactCLI.swift")
    if not member.isfile() or member.size > 1_000_000:
        raise SystemExit("Invalid CLI source in archive")
    content = source.extractfile(member).read().decode("utf-8")
    if f'print("contactctl {version}")' not in content:
        raise SystemExit("Archive CLI version does not match the release tag")

template = Path(__file__).resolve().parent.parent / "packaging/homebrew/contactctl.rb.in"
result = template.read_text().replace("@TAG@", tag).replace("@VERSION@", version)
result = result.replace("@SHA256@", hashlib.sha256(archive.read_bytes()).hexdigest())
print(result, end="")
