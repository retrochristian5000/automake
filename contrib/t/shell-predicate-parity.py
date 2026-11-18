#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise Automake's test/[ shell selection through real Autoconf output."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURE = (
    "    _AM_CHECK_SHELL_FEATURE([$1],\n"
    "      [checks POSIX test and bracket predicates consistently],\n"
    "      ["
)
END = "],\n      [], [am_score=1; break])"


def shell_check_body(source: str) -> str:
    if source.count(FEATURE) != 1:
        raise AssertionError("Automake shell feature check is missing or duplicated")
    remainder = source.split(FEATURE, 1)[1]
    if END not in remainder:
        raise AssertionError("Automake shell feature check is incomplete")
    body = remainder.split(END, 1)[0]
    for fragment in (
        "test -e config.log && [[ -e config.log ]]",
        "test -d . && [[ -d . ]]",
        "test ! -e nonesuch && [[ ! -e nonesuch ]]",
        'test -n "a b" && [[ -n "a b" ]]',
        'test -z "" && [[ -z "" ]]',
        "test 7 -eq 7 && [[ 7 -eq 7 ]]",
    ):
        if fragment not in body:
            raise AssertionError(f"Automake shell check lacks paired condition: {fragment}")
    return body


def run(command: list[str], directory: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["CONFIG_SITE"] = "/dev/null"
    env["LC_ALL"] = "C"
    return subprocess.run(
        command, cwd=directory, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def main() -> int:
    if not shutil.which("autoconf"):
        raise RuntimeError("native Autoconf is needed to test shell macro expansion")
    body = shell_check_body((ROOT / "configure.ac").read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="whp-automake-shell-") as tmp:
        directory = Path(tmp)
        (directory / "configure.ac").write_text(
            "AC_INIT([whp-automake-shell-parity], [1])\n"
            "AC_DEFUN([WHP_CHECK_SHELL_PREDICATES], [\n"
            "if " + body + "; then\n"
            "  AC_MSG_NOTICE([WHP shell predicate parity: PASS])\n"
            "else\n"
            "  AC_MSG_ERROR([WHP shell predicate parity: FAIL])\n"
            "fi])\n"
            "WHP_CHECK_SHELL_PREDICATES\n"
            "AC_OUTPUT\n",
            encoding="utf-8",
        )
        generated = run(["autoconf"], directory)
        if generated.returncode != 0:
            raise AssertionError("Autoconf macro expansion failed:\n" + generated.stderr)
        configure = directory / "configure"
        expanded = configure.read_text(encoding="utf-8")
        if "[ -e config.log ]" not in expanded:
            raise AssertionError("m4 consumed shell bracket expressions")
        passing = run(["/bin/sh", str(configure)], directory)
        if passing.returncode != 0 or "WHP shell predicate parity: PASS" not in passing.stdout:
            raise AssertionError("POSIX shell failed paired predicates:\n"
                                 + passing.stdout + passing.stderr)

        # A test-only injected bracket failure must be reported as a failure.
        # This verifies that shell discovery cannot claim a passing runner
        # when 'test' succeeds but the corresponding '[' test does not.
        poisoned = directory / "configure-poisoned"
        poisoned.write_text(
            expanded.replace("[ -e config.log ]", "false", 1),
            encoding="utf-8",
        )
        failed = run(["/bin/sh", str(poisoned)], directory)
        if failed.returncode == 0:
            raise AssertionError("broken bracket predicate passed the shell probe")

    print("WHP Automake POSIX test/bracket shell probe: verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
