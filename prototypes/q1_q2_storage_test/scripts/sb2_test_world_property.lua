-- sb2_test_world_property.lua
-- Prototype Q1: overuje world.setProperty size limit a cross-world scope.
-- Used by: sb2_test_terminal.lua (ScriptPane callback handler)
-- Performance: one-time (nie hot path, nie per-tick)
-- Lua 5.1 striktne – ziadne goto, ziadne //, ziadne bitwise operatory

-- Exportovana tabulka – pristupna cez global sb2TestWorldProperty.<func>()
sb2TestWorldProperty = {}

-- Kluce ktore test pouziva (pre cleanup)
local SB2_TEST_KEYS = {
  "sb2_test_prop_1kb",
  "sb2_test_prop_10kb",
  "sb2_test_prop_50kb",
  "sb2_test_prop_100kb",
  "sb2_test_prop_250kb",
  "sb2_test_prop_500kb",
  "sb2_test_prop_1024kb",
  "sb2_test_prop_5120kb",
  "sb2_test_nil_behavior",
  "sb2_test_xworld_marker"
}

-- Velkosti v KB pre size sweep (v presnom poradi podla planu)
local SIZE_SWEEP_KB = {1, 10, 50, 100, 250, 500, 1024, 5120}

-- Interne: bezpecny log helper
local function log(msg)
  sb.logInfo(msg)
end

-- Interne: pokusi sa zapisat a precitat property, vracia tabulku s vysledkami
-- stable API: nie, internal helper
local function _trySizeEntry(key, payload)
  local result = {}
  result.write_ok = false
  result.write_err = nil
  result.read_ok = false
  result.read_err = nil
  result.integrity = false

  -- write probe
  local write_ok, write_err = pcall(function()
    world.setProperty(key, payload)
  end)
  if write_ok then
    result.write_ok = true
  else
    result.write_err = tostring(write_err)
    -- Pri write failure nemozeme robiť read integrity test
    return result
  end

  -- read probe
  local read_ok, read_val_or_err = pcall(function()
    return world.getProperty(key)
  end)
  if not read_ok then
    result.read_err = tostring(read_val_or_err)
    return result
  end

  result.read_ok = true
  local read_val = read_val_or_err

  -- integrity check: dlzka aj obsah
  if read_val == nil then
    result.integrity = false
    result.read_err = "getProperty returned nil"
  elseif type(read_val) ~= "string" then
    result.integrity = false
    result.read_err = "getProperty returned non-string type: " .. type(read_val)
  elseif #read_val ~= #payload then
    result.integrity = false
    result.read_err = "length mismatch: expected " .. #payload .. " got " .. #read_val
  elseif read_val ~= payload then
    result.integrity = false
    result.read_err = "content mismatch (lengths match but bytes differ)"
  else
    result.integrity = true
  end

  return result
end

-- Interne: zformatuje riadok vysledku size sweep
local function _formatSweepRow(size_kb, r)
  local write_str, read_str, integ_str

  if r.write_ok then
    write_str = "OK"
  else
    write_str = "FAIL (pcall err: " .. (r.write_err or "unknown") .. ")"
  end

  if not r.write_ok then
    read_str = "N/A"
    integ_str = "N/A"
  elseif r.read_ok then
    read_str = "OK"
    if r.integrity then
      integ_str = "PASS"
    else
      integ_str = "FAIL (" .. (r.read_err or "unknown") .. ")"
    end
  else
    read_str = "FAIL (pcall err: " .. (r.read_err or "unknown") .. ")"
    integ_str = "N/A"
  end

  -- Zarovnanie: padneme na 7 znakov (5120 je max)
  local size_str = string.format("%4d KB", size_kb)
  return "[SB2_TEST_Q1] " .. size_str .. " -> write: " .. write_str .. " | read: " .. read_str .. " | integrity: " .. integ_str
end

-- PUBLIC: Spusti kompletny size sweep test + nil-behavior test + logtrunc probe.
-- Side effects: zapisuje testovacie world.properties, na konci ich vymazava.
-- stable API: nie (disposable prototype)
function sb2TestWorldProperty.runSizeTest()
  log("[SB2_TEST_Q1] ========================================")
  log("[SB2_TEST_Q1] world.setProperty size sweep")
  log("[SB2_TEST_Q1] ========================================")

  -- Detekcia world type
  local world_type = "unknown"
  local wt_ok, wt_val = pcall(function() return world.type() end)
  if wt_ok and wt_val ~= nil then
    world_type = tostring(wt_val)
  end
  log("[SB2_TEST_Q1] World type: " .. world_type)

  -- --- Sub-test 1: Size limit sweep ---
  local first_fail_kb = nil
  local last_pass_kb = nil
  local sweep_results = {}

  for _, size_kb in ipairs(SIZE_SWEEP_KB) do
    local size_bytes = size_kb * 1024
    local key = "sb2_test_prop_" .. size_kb .. "kb"
    -- Deterministicky payload: string.rep("x", ...)
    local payload = string.rep("x", size_bytes)

    local r = _trySizeEntry(key, payload)
    sweep_results[size_kb] = r

    log(_formatSweepRow(size_kb, r))

    -- Sledujeme prvy fail a posledny pass (nevraciame sa ani pri faile)
    if r.write_ok and r.read_ok and r.integrity then
      last_pass_kb = size_kb
    elseif first_fail_kb == nil then
      first_fail_kb = size_kb
    end
  end

  -- Zhrnutie limitu
  if first_fail_kb == nil then
    log("[SB2_TEST_Q1] LIMIT DETECTED: All sizes passed. No hard limit found up to 5120 KB.")
  elseif last_pass_kb == nil then
    log("[SB2_TEST_Q1] LIMIT DETECTED: All sizes failed. Limit is below 1 KB.")
  else
    log("[SB2_TEST_Q1] LIMIT DETECTED between " .. last_pass_kb .. " KB and " .. first_fail_kb .. " KB")
  end

  -- --- Sub-test 2: setProperty(key, nil) behavior ---
  log("[SB2_TEST_Q1] ----------------------------------------")
  log("[SB2_TEST_Q1] nil-behavior test")

  local nil_key = "sb2_test_nil_behavior"
  local nil_delete_works = false  -- pouzijeme pre cleanup

  -- Najprv zapiseme hodnotu
  local set_ok, set_err = pcall(function()
    world.setProperty(nil_key, "hello")
  end)
  if not set_ok then
    log("[SB2_TEST_Q1] NIL_BEHAVIOR: SKIP (initial write failed: " .. tostring(set_err) .. ")")
  else
    -- Overime ze existuje
    local check_ok, check_val = pcall(function() return world.getProperty(nil_key) end)
    if not check_ok or check_val ~= "hello" then
      log("[SB2_TEST_Q1] NIL_BEHAVIOR: SKIP (pre-nil read failed or wrong value)")
    else
      -- Skusime nastavit nil
      local nil_set_ok, nil_set_err = pcall(function()
        world.setProperty(nil_key, nil)
      end)

      if not nil_set_ok then
        log("[SB2_TEST_Q1] NIL_BEHAVIOR: delete invalid (err: " .. tostring(nil_set_err) .. ")")
        -- nil-set zlyhal, kluc treba pocistat inak
        nil_delete_works = false
      else
        -- Preverime co sa stalo
        local after_ok, after_val = pcall(function() return world.getProperty(nil_key) end)
        if not after_ok then
          log("[SB2_TEST_Q1] NIL_BEHAVIOR: post-nil read error: " .. tostring(after_val))
        elseif after_val == nil then
          log("[SB2_TEST_Q1] NIL_BEHAVIOR: delete OK (key removed)")
          nil_delete_works = true
        elseif after_val == "hello" then
          log("[SB2_TEST_Q1] NIL_BEHAVIOR: no-op (key persists with original value)")
          nil_delete_works = false
        else
          log("[SB2_TEST_Q1] NIL_BEHAVIOR: unexpected value after nil: " .. tostring(after_val))
          nil_delete_works = false
        end
      end
    end
  end

  -- --- Sub-test 3: Log truncation informational probe ---
  log("[SB2_TEST_Q1] ----------------------------------------")
  log("[SB2_TEST_Q1] Log truncation probe (10 KB payload to sb.logInfo)")

  -- 10 KB deterministicky string: 1280 * "ABCDEFGH" = 10240 znakov
  local logtrunc_payload = string.rep("ABCDEFGH", 1280)
  local logtrunc_ok, logtrunc_err = pcall(function()
    sb.logInfo("[SB2_TEST_Q1] LOGTRUNC_PROBE: " .. logtrunc_payload)
  end)
  if not logtrunc_ok then
    log("[SB2_TEST_Q1] LOGTRUNC_PROBE: sb.logInfo itself errored: " .. tostring(logtrunc_err))
  end
  -- Nasledujuci riadok sluzi ako koniec-marker pre manualne overenie
  log("[SB2_TEST_Q1] LOGTRUNC_PROBE: end-marker (user must verify previous line in log file)")
  log("[SB2_TEST_Q1] LOGTRUNC_PROBE: expected line length (with prefix) = " .. (string.len("[SB2_TEST_Q1] LOGTRUNC_PROBE: ") + #logtrunc_payload))

  -- --- Sub-test 4: Cleanup sweep ---
  log("[SB2_TEST_Q1] ----------------------------------------")
  log("[SB2_TEST_Q1] Cleanup sweep")

  -- Cleanup klucov zo size sweep
  for _, size_kb in ipairs(SIZE_SWEEP_KB) do
    local key = "sb2_test_prop_" .. size_kb .. "kb"
    local r = sweep_results[size_kb]
    -- Pokusame sa o cleanup iba ak write prebehol (inak kluc neexistuje)
    if r and r.write_ok then
      -- Skus nil prvy
      local clean_ok, clean_err = pcall(function()
        world.setProperty(key, nil)
      end)
      if clean_ok then
        log("[SB2_TEST_Q1] CLEANUP: " .. key .. " via nil")
      else
        -- Fallback: prazdny string
        local clean2_ok, clean2_err = pcall(function()
          world.setProperty(key, "")
        end)
        if clean2_ok then
          log("[SB2_TEST_Q1] CLEANUP: " .. key .. " via empty-string (nil failed: " .. tostring(clean_err) .. ")")
        else
          log("[SB2_TEST_Q1] CLEANUP: " .. key .. " FAILED both nil and empty-string")
        end
      end
    end
  end

  -- Cleanup nil_behavior key (ak este existuje)
  if not nil_delete_works then
    -- Skusime nil este raz (mozno uz funguje), potom empty string
    local cn_ok, cn_err = pcall(function() world.setProperty(nil_key, nil) end)
    if cn_ok then
      log("[SB2_TEST_Q1] CLEANUP: " .. nil_key .. " via nil")
    else
      local ce_ok, ce_err = pcall(function() world.setProperty(nil_key, "") end)
      if ce_ok then
        log("[SB2_TEST_Q1] CLEANUP: " .. nil_key .. " via empty-string")
      else
        log("[SB2_TEST_Q1] CLEANUP: " .. nil_key .. " FAILED cleanup")
      end
    end
  else
    log("[SB2_TEST_Q1] CLEANUP: " .. nil_key .. " already removed (nil-delete worked)")
  end

  log("[SB2_TEST_Q1] ========================================")
  log("[SB2_TEST_Q1] runSizeTest COMPLETE. Check starbound.log for results.")
  log("[SB2_TEST_Q1] ========================================")
end

-- PUBLIC: Cross-world scope test – krok 1 z 4.
-- Zapise marker na AKTUALNOM svete. Pouzivatel potom warpne na INY svet.
-- stable API: nie (disposable prototype)
function sb2TestWorldProperty.crossWorldStep1Write()
  log("[SB2_TEST_Q1_XW] Step 1: Writing marker on CURRENT world (world A)")

  local wt_ok, wt_val = pcall(function() return world.type() end)
  local world_type = (wt_ok and wt_val ~= nil) and tostring(wt_val) or "unknown"
  log("[SB2_TEST_Q1_XW] Current world type: " .. world_type)

  local ok, err = pcall(function()
    world.setProperty("sb2_test_xworld_marker", "world_A_value")
  end)
  if ok then
    log("[SB2_TEST_Q1_XW] Step 1 DONE. Marker 'world_A_value' written.")
    log("[SB2_TEST_Q1_XW] >> USER ACTION: Warp to a DIFFERENT planet/world, then call crossWorldStep2Read()")
  else
    log("[SB2_TEST_Q1_XW] Step 1 FAILED: " .. tostring(err))
  end
end

-- PUBLIC: Cross-world scope test – krok 2 z 4.
-- Cita marker na NOVOM svete (kam hrac priletel). Ak je scope per-world, vrati nil.
-- stable API: nie (disposable prototype)
function sb2TestWorldProperty.crossWorldStep2Read()
  log("[SB2_TEST_Q1_XW] Step 2: Reading marker on NEW world (world B)")

  local wt_ok, wt_val = pcall(function() return world.type() end)
  local world_type = (wt_ok and wt_val ~= nil) and tostring(wt_val) or "unknown"
  log("[SB2_TEST_Q1_XW] Current world type: " .. world_type)

  local ok, val = pcall(function() return world.getProperty("sb2_test_xworld_marker") end)
  if not ok then
    log("[SB2_TEST_Q1_XW] Step 2 READ ERROR: " .. tostring(val))
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: undefined (read error on world B)")
    return
  end

  log("[SB2_TEST_Q1_XW] Step 2 value on world B: " .. tostring(val))

  if val == "world_A_value" then
    log("[SB2_TEST_Q1_XW] PRELIMINARY: value visible -> possibly universe-scope (or same world loaded again)")
  elseif val == nil then
    log("[SB2_TEST_Q1_XW] PRELIMINARY: nil on world B -> per-world scope (Step 3+4 will confirm)")
  else
    log("[SB2_TEST_Q1_XW] PRELIMINARY: unexpected value: " .. tostring(val))
  end

  log("[SB2_TEST_Q1_XW] >> USER ACTION: Call crossWorldStep3Overwrite() NOW (still on world B), then warp back to world A")
end

-- PUBLIC: Cross-world scope test – krok 3 z 4.
-- Zapise ODLISNU hodnotu na CIELOVOM svete (B). Pouzivatel potom warpne spat na A.
-- stable API: nie (disposable prototype)
function sb2TestWorldProperty.crossWorldStep3Overwrite()
  log("[SB2_TEST_Q1_XW] Step 3: Overwriting marker on world B with 'world_B_value'")

  local ok, err = pcall(function()
    world.setProperty("sb2_test_xworld_marker", "world_B_value")
  end)
  if ok then
    log("[SB2_TEST_Q1_XW] Step 3 DONE. Marker 'world_B_value' written on world B.")
    log("[SB2_TEST_Q1_XW] >> USER ACTION: Warp BACK to world A, then call crossWorldStep4Verify()")
  else
    log("[SB2_TEST_Q1_XW] Step 3 FAILED: " .. tostring(err))
    log("[SB2_TEST_Q1_XW] >> Still warp back to world A and call crossWorldStep4Verify() for partial data")
  end
end

-- PUBLIC: Cross-world scope test – krok 4 z 4.
-- Cita marker na POVODNOM svete (A) a vynasa verdikt o scope.
-- stable API: nie (disposable prototype)
function sb2TestWorldProperty.crossWorldStep4Verify()
  log("[SB2_TEST_Q1_XW] Step 4: Verifying marker on world A (original world)")

  local wt_ok, wt_val = pcall(function() return world.type() end)
  local world_type = (wt_ok and wt_val ~= nil) and tostring(wt_val) or "unknown"
  log("[SB2_TEST_Q1_XW] Current world type: " .. world_type)

  local ok, val = pcall(function() return world.getProperty("sb2_test_xworld_marker") end)
  if not ok then
    log("[SB2_TEST_Q1_XW] Step 4 READ ERROR: " .. tostring(val))
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: undefined (read error on return to world A)")
    return
  end

  log("[SB2_TEST_Q1_XW] Step 4 value on world A: " .. tostring(val))

  -- Verdikt
  if val == "world_A_value" then
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: per-world")
    log("[SB2_TEST_Q1_XW] CONCLUSION: world.setProperty is per-world (world B overwrite did NOT affect world A)")
  elseif val == "world_B_value" then
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: universe")
    log("[SB2_TEST_Q1_XW] CONCLUSION: world.setProperty is universe-scope (world B overwrite DID propagate to world A)")
  elseif val == nil then
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: undefined (value is nil on world A – key may have been lost)")
  else
    log("[SB2_TEST_Q1_XW] WORLD_PROPERTY_SCOPE: undefined (unexpected value: " .. tostring(val) .. ")")
  end

  -- Cleanup
  local cl_ok, cl_err = pcall(function() world.setProperty("sb2_test_xworld_marker", nil) end)
  if cl_ok then
    log("[SB2_TEST_Q1_XW] CLEANUP: sb2_test_xworld_marker removed via nil")
  else
    local cl2_ok = pcall(function() world.setProperty("sb2_test_xworld_marker", "") end)
    if cl2_ok then
      log("[SB2_TEST_Q1_XW] CLEANUP: sb2_test_xworld_marker cleared via empty-string")
    else
      log("[SB2_TEST_Q1_XW] CLEANUP: sb2_test_xworld_marker cleanup FAILED – remove manually")
    end
  end

  log("[SB2_TEST_Q1_XW] Cross-world scope test COMPLETE.")
end
