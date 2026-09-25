#!/usr/bin/env python3
"""Spusti standalone Lua testy z mod/tests/ pod Lua 5.1, 5.3 a 5.4 (cez lupa).

Starbound nema CI; toto je dev-only runner pre ciste moduly (bez engine API).
Pouzitie z korena repa:  python3 tools/run_lua_tests.py [nazov_testu ...]
Vyzaduje: pip install lupa
"""
import glob, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

def load_configs(runtime):
    configs = {}
    for path in glob.glob("mod/configs/*.config"):
        with open(path, encoding="utf-8") as fh:
            configs["/" + os.path.relpath(path, "mod").replace(os.sep, "/")] = json.load(fh)
    runtime.globals()["SB2_TEST_CONFIGS"] = runtime.table_from(configs, recursive=True)

def run(modname, test_files):
    try:
        mod = __import__(modname, fromlist=["LuaRuntime"])
    except ImportError:
        print(f"== {modname}: not available, skipped")
        return 0
    failures = 0
    for test in test_files:
        rt = mod.LuaRuntime(unpack_returned_tuples=True)
        load_configs(rt)
        print(f"== {modname} {rt.eval('_VERSION')} :: {test}")
        try:
            rt.execute(open(test, encoding="utf-8").read())
        except Exception as exc:  # noqa: BLE001
            print(f"ERROR {exc}")
            failures += 1
            continue
        failures += int(rt.globals()["SB2_TEST_FAILURES"] or 0)
    return failures

def main():
    wanted = sys.argv[1:]
    tests = sorted(glob.glob("mod/tests/*_test.lua"))
    if wanted:
        tests = [t for t in tests if any(w in t for w in wanted)]
    total = 0
    for modname in ("lupa.lua51", "lupa.lua53", "lupa.lua54"):
        total += run(modname, tests)
    print("=" * 40)
    print("ALL PASS" if total == 0 else f"{total} FAILED")
    sys.exit(1 if total else 0)

if __name__ == "__main__":
    main()
