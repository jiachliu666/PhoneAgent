#!/usr/bin/env python3
import plistlib
import sys
from typing import Dict, List, Tuple


def die(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def parse_kv(args: List[str]) -> Dict[str, str]:
    env: Dict[str, str] = {}
    for a in args:
        if "=" not in a:
            die(f"Expected KEY=VALUE, got: {a}")
        k, v = a.split("=", 1)
        k = k.strip()
        if not k:
            die(f"Empty key in: {a}")
        env[k] = v
    return env


def iter_test_targets(xctestrun: dict) -> List[Tuple[int, int, dict]]:
    out: List[Tuple[int, int, dict]] = []
    for ci, conf in enumerate(xctestrun.get("TestConfigurations", [])):
        for ti, t in enumerate(conf.get("TestTargets", [])):
            out.append((ci, ti, t))
    return out


def main() -> None:
    if len(sys.argv) < 3:
        die("Usage: patch_xctestrun_env.py <path.xctestrun> KEY=VALUE [KEY=VALUE ...]")

    path = sys.argv[1]
    env = parse_kv(sys.argv[2:])

    with open(path, "rb") as f:
        xctestrun = plistlib.load(f)

    targets = iter_test_targets(xctestrun)
    if not targets:
        die(f"No TestTargets found in {path}")

    patched = 0
    for _, _, t in targets:
        tb = t.get("TestBundlePath", "")
        # Only patch our UI test target to avoid surprising side-effects.
        if "PhoneAgentUITests.xctest" not in str(tb):
            continue

        for key in ("EnvironmentVariables", "TestingEnvironmentVariables"):
            cur = t.get(key)
            if not isinstance(cur, dict):
                cur = {}
            cur.update(env)
            t[key] = cur
        patched += 1

    if patched == 0:
        die(f"Did not find PhoneAgentUITests.xctest in any TestTargets in {path}")

    with open(path, "wb") as f:
        plistlib.dump(xctestrun, f, fmt=plistlib.FMT_XML, sort_keys=False)

    print(f"Patched {patched} test target(s) in {path}")


if __name__ == "__main__":
    main()

