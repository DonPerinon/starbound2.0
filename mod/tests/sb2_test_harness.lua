-- mod/tests/sb2_test_harness.lua
-- Minimalny test harness pre standalone Lua testy (mimo Starbound).
-- Pouzitie: local t = require("sb2_test_harness"); t.check(cond, "label"); t.finish()
-- Vysledok: globalna SB2_TEST_FAILURES (pocet zlyhani), tools/run_lua_tests.py ju cita.

local harness = {}
local failures = 0
local passes = 0

function harness.check(condition, label)
  if condition then
    passes = passes + 1
    print("PASS  " .. label)
  else
    failures = failures + 1
    print("FAIL  " .. label)
  end
end

function harness.approx(actual, expected, tolerance, label)
  local ok = type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1e-6)
  harness.check(ok, string.format("%s (got %s, want %s)", label, tostring(actual), tostring(expected)))
end

function harness.expectError(fn, pattern, label)
  local ok, err = pcall(fn)
  local matched = (not ok) and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil)
  harness.check(matched, label .. (ok and " (no error raised)" or (matched and "" or " (unexpected: " .. tostring(err) .. ")")))
end

function harness.finish()
  print(string.rep("-", 40))
  print(string.format("%d passed, %d failed", passes, failures))
  SB2_TEST_FAILURES = (SB2_TEST_FAILURES or 0) + failures
  return failures
end

return harness
