#!/usr/bin/env python3
"""Exercise only help/version and invalid input: never request Contacts access."""
import subprocess
import sys

binary = sys.argv[1] if len(sys.argv) > 1 else ".build/release/contactctl"


def run(arguments, expected_code, expected_text, stderr=False):
    result = subprocess.run([binary, *arguments], capture_output=True, text=True, timeout=10)
    assert result.returncode == expected_code, (arguments, result)
    assert expected_text in (result.stderr if stderr else result.stdout), (arguments, result)


run(["--version"], 0, "contactctl ")
run(["help"], 0, "--dry-run")
run(["delete", "--help"], 0, "--yes is required")
for args, message in [
    (["delete", "synthetic-id"], "usage: contactctl delete"),
    (["delete", "synthetic-id", "--json"], "usage: contactctl delete"),
    (["delete", "synthetic-id", "--dry-run", "--bogus"], "usage: contactctl delete"),
    (["update", "synthetic-id", "--json"], "update requires"),
    (["update", "synthetic-id", "--photo", "/nonexistent-contactctl-photo.png"], "cannot read --photo"),
    (["search", "Ada", "--limit", "0"], "--limit requires"),
    (["search", " "], "usage: contactctl search"),
    (["show", ""], "usage: contactctl show"),
]:
    run(args, 1, message, stderr=True)
print("CLI smoke checks passed (no Contacts access).")
