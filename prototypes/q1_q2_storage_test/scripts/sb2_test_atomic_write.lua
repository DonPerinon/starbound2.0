-- sb2_test_atomic_write.lua
-- Prototype Q2: overuje dostupne metody atomic file write v Starbound Lua sandboxe.
-- Testuje: root.assetJson write probe, io.* sandbox probe, chunked world.setProperty.
-- Used by: sb2_test_terminal.lua (ScriptPane callback handler)
-- Performance: one-time (nie hot path, nie per-tick)
-- Lua 5.1 striktne – ziadne goto, ziadne //, ziadne bitwise operatory

-- Exportovana tabulka – pristupna cez global sb2TestAtomicWrite.<func>()
sb2TestAtomicWrite = {}

-- Konstanty
local SB2_TMP_FILE = "/tmp/sb2_test_atomic.txt"
local SB2_CHUNK_KEY_1 = "sb2_test_univ_chunk_1"
local SB2_CHUNK_KEY_2 = "sb2_test_univ_chunk_2"
local SB2_CHUNK_SIZE_KB = 25  -- kazdý chunk ~25 KB, spolu ~50 KB

-- Interne: bezpecny log helper
local function log(msg)
  sb.logInfo(msg)
end

-- Interne: skusi zavolat metodu na tabulke (napr. root["setAssetJson"])
-- Vracia "not_a_function" | "error:<msg>" | "ok"
local function _probeSymbol(tbl, symbol_name, arg1, arg2)
  local fn = tbl[symbol_name]
  if type(fn) ~= "function" then
    return "not_a_function"
  end
  local ok, err = pcall(fn, arg1, arg2)
  if ok then
    return "ok"
  else
    return "error:" .. tostring(err)
  end
end

-- --- Sub-test 1: root.assetJson write probe ---
local function _runAssetJsonProbe()
  log("[SB2_TEST_Q2] ----------------------------------------")
  log("[SB2_TEST_Q2] Sub-test 1: root.assetJson probe")

  -- Read probe: skusime precitat neexistujuci asset (ocakavame "no such asset" error)
  local read_ok, read_val = pcall(function()
    return root.assetJson("/sb2_nonexistent_probe_path.config")
  end)
  if read_ok then
    log("[SB2_TEST_Q2] ASSETJSON_READ: available (returned value for nonexistent path – unexpected)")
  else
    local err_str = tostring(read_val)
    if err_str:find("no such asset") or err_str:find("not found") or err_str:find("Unknown") then
      log("[SB2_TEST_Q2] ASSETJSON_READ: available (function exists, returns expected 'no such asset' error)")
    else
      log("[SB2_TEST_Q2] ASSETJSON_READ: error (" .. err_str .. ")")
    end
  end

  -- Write probe: skusime rozne mozne nazvy write funkcie
  local write_candidates = {
    "setAssetJson",
    "writeAssetJson",
    "assetJsonWrite",
    "writeJson",
    "setJson"
  }

  local write_verdict = "unavailable"
  for _, name in ipairs(write_candidates) do
    local result = _probeSymbol(root, name, "/sb2_probe_write_test.config", {probe = true})
    log("[SB2_TEST_Q2] ASSETJSON_WRITE." .. name .. ": " .. result)
    if result == "ok" then
      write_verdict = "ok via root." .. name
    end
  end

  log("[SB2_TEST_Q2] ASSETJSON_WRITE: " .. write_verdict)
end

-- --- Sub-test 2: io.* sandbox probe ---
local function _runIoSandboxProbe()
  log("[SB2_TEST_Q2] ----------------------------------------")
  log("[SB2_TEST_Q2] Sub-test 2: io.* sandbox probe")

  -- Overime ci io tabulka existuje
  local io_type = type(io)
  if io_type == "nil" then
    log("[SB2_TEST_Q2] IO_SANDBOX: io table is nil (fully blocked)")
    return false  -- io nedostupne
  end

  log("[SB2_TEST_Q2] IO_SANDBOX: io table exists (type=" .. io_type .. ")")

  -- Skusime io.open pre zapis
  local open_ok, open_result = pcall(function()
    return io.open(SB2_TMP_FILE, "w")
  end)

  if not open_ok then
    log("[SB2_TEST_Q2] IO_SANDBOX: io.open errored (err: " .. tostring(open_result) .. ")")
    return false
  end

  local handle = open_result
  if handle == nil then
    -- io.open vraci nil, err pri blokaci (Lua konvencia)
    log("[SB2_TEST_Q2] IO_SANDBOX: io.open blocked (returned nil – no error message captured)")
    return false
  end

  -- Pozor: ak io.open vracia dve hodnoty (handle, err), pcall zabaluje do jednej
  -- Overime ci je handle skutocne file object (ma metodu write)
  if type(handle) ~= "userdata" and type(handle) ~= "table" then
    log("[SB2_TEST_Q2] IO_SANDBOX: io.open returned unexpected type: " .. type(handle))
    return false
  end

  log("[SB2_TEST_Q2] IO_SANDBOX: io.open returns handle (type=" .. type(handle) .. ")")

  -- Skusime write
  local write_ok, write_err = pcall(function()
    handle:write("test_payload_123")
  end)
  if write_ok then
    log("[SB2_TEST_Q2] IO_SANDBOX: handle:write OK")
  else
    log("[SB2_TEST_Q2] IO_SANDBOX: handle:write failed: " .. tostring(write_err))
  end

  -- Zatvorime handle
  local close_ok, close_err = pcall(function() handle:close() end)
  if close_ok then
    log("[SB2_TEST_Q2] IO_SANDBOX: handle:close OK")
  else
    log("[SB2_TEST_Q2] IO_SANDBOX: handle:close failed: " .. tostring(close_err))
  end

  -- Verifikacia: skus precitat co sme zapisali
  local verify_ok, verify_handle = pcall(function()
    return io.open(SB2_TMP_FILE, "r")
  end)
  if verify_ok and verify_handle ~= nil then
    local content_ok, content = pcall(function()
      return verify_handle:read("*a")
    end)
    pcall(function() verify_handle:close() end)
    if content_ok then
      log("[SB2_TEST_Q2] IO_SANDBOX: read-back content = '" .. tostring(content) .. "'")
      if content == "test_payload_123" then
        log("[SB2_TEST_Q2] IO_SANDBOX: read-back integrity PASS")
      else
        log("[SB2_TEST_Q2] IO_SANDBOX: read-back integrity FAIL (content mismatch)")
      end
    else
      log("[SB2_TEST_Q2] IO_SANDBOX: read-back read error: " .. tostring(content))
    end
  else
    log("[SB2_TEST_Q2] IO_SANDBOX: read-back open failed")
  end

  -- Crash-mid-write simulacia
  log("[SB2_TEST_Q2] IO_SANDBOX: crash-mid-write simulation")
  local crash_handle = nil
  local crash_open_ok, crash_open_result = pcall(function()
    return io.open(SB2_TMP_FILE, "w")  -- prepise existujuci subor
  end)
  if crash_open_ok and crash_open_result ~= nil then
    crash_handle = crash_open_result
    pcall(function() crash_handle:write("first_half_only") end)
    -- Simulujeme crash: error() v pcall – close sa NESTIHNE
    local sim_ok, sim_err = pcall(function()
      error("sb2_simulated_crash")
    end)
    -- sim_ok je false, crash_handle zostal otvoreny bez close
    log("[SB2_TEST_Q2] IO_SANDBOX: crash simulated, handle NOT explicitly closed")
    -- Pokusame sa o close aby sme neviedli leak (Lua GC moze zatvoric, ale nie zarucene)
    local defer_close_ok, defer_close_err = pcall(function() crash_handle:close() end)
    if defer_close_ok then
      log("[SB2_TEST_Q2] IO_SANDBOX: deferred close succeeded (GC/manual close works after pcall error)")
    else
      log("[SB2_TEST_Q2] IO_SANDBOX: deferred close failed: " .. tostring(defer_close_err))
    end
    log("[SB2_TEST_Q2] IO_SANDBOX: check " .. SB2_TMP_FILE .. " manually – should contain 'first_half_only'")
  else
    log("[SB2_TEST_Q2] IO_SANDBOX: crash-mid-write: open for simulation failed")
  end

  return true  -- io.open fungovalo
end

-- --- Sub-test 3: chunked world.setProperty workaround ---
local function _runChunkedWspTest()
  log("[SB2_TEST_Q2] ----------------------------------------")
  log("[SB2_TEST_Q2] Sub-test 3: chunked world.setProperty workaround")

  local chunk_size_bytes = SB2_CHUNK_SIZE_KB * 1024

  -- Deterministicky payload ~50 KB: string.rep("SB2ECON", ...) dokola
  -- "SB2ECON" = 7 znakov, 50 KB = 51200 znakov -> 51200 / 7 ~ 7314 opakovani = 51198 znakov
  -- Pouzijeme presne chunk_size_bytes * 2 pre round number
  local total_bytes = chunk_size_bytes * 2
  local unit = "SB2ECON"  -- 7 znakov
  local repeats = math.floor(total_bytes / #unit)
  local original_payload = string.rep(unit, repeats)
  -- Dorovname na presnu dlzku
  local diff = total_bytes - #original_payload
  if diff > 0 then
    original_payload = original_payload .. string.sub(unit, 1, diff)
  end

  log("[SB2_TEST_Q2] CHUNKED_WSP: original payload size = " .. #original_payload .. " bytes (" .. math.floor(#original_payload / 1024) .. " KB)")

  -- Rozdelenie na 2 chunky
  local chunk1 = string.sub(original_payload, 1, chunk_size_bytes)
  local chunk2 = string.sub(original_payload, chunk_size_bytes + 1)

  log("[SB2_TEST_Q2] CHUNKED_WSP: chunk1=" .. #chunk1 .. "B chunk2=" .. #chunk2 .. "B")

  -- Zapis oboch chunkov
  local w1_ok, w1_err = pcall(function()
    world.setProperty(SB2_CHUNK_KEY_1, chunk1)
  end)
  local w2_ok, w2_err = pcall(function()
    world.setProperty(SB2_CHUNK_KEY_2, chunk2)
  end)

  if not w1_ok then
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk1 write FAILED: " .. tostring(w1_err))
  end
  if not w2_ok then
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk2 write FAILED: " .. tostring(w2_err))
  end

  if not (w1_ok and w2_ok) then
    log("[SB2_TEST_Q2] CHUNKED_WSP: round-trip FAIL (write error), chunk_size=" .. SB2_CHUNK_SIZE_KB .. "KB")
    return
  end

  -- Round-trip read + reassemble
  local r1_ok, r1_val = pcall(function() return world.getProperty(SB2_CHUNK_KEY_1) end)
  local r2_ok, r2_val = pcall(function() return world.getProperty(SB2_CHUNK_KEY_2) end)

  if not r1_ok then
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk1 read FAILED: " .. tostring(r1_val))
    log("[SB2_TEST_Q2] CHUNKED_WSP: round-trip FAIL (read error), chunk_size=" .. SB2_CHUNK_SIZE_KB .. "KB")
    return
  end
  if not r2_ok then
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk2 read FAILED: " .. tostring(r2_val))
    log("[SB2_TEST_Q2] CHUNKED_WSP: round-trip FAIL (read error), chunk_size=" .. SB2_CHUNK_SIZE_KB .. "KB")
    return
  end

  local reassembled = (r1_val or "") .. (r2_val or "")

  if reassembled == original_payload then
    log("[SB2_TEST_Q2] CHUNKED_WSP: round-trip PASS, chunk_size=" .. SB2_CHUNK_SIZE_KB .. "KB")
  else
    log("[SB2_TEST_Q2] CHUNKED_WSP: round-trip FAIL (content mismatch), reassembled_len=" .. #reassembled .. " expected=" .. #original_payload .. ", chunk_size=" .. SB2_CHUNK_SIZE_KB .. "KB")
  end

  -- Crash-mid-write simulacia (zapiseme iba chunk1, nie chunk2)
  log("[SB2_TEST_Q2] CHUNKED_WSP: crash-mid-write simulation (writing only chunk1)")
  local sim_chunk_marker = "CRASH_SIMULATION_VALUE"
  local sim_ok_1, sim_err_1 = pcall(function()
    world.setProperty(SB2_CHUNK_KEY_1, sim_chunk_marker)
  end)
  if sim_ok_1 then
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk1 overwritten with simulation marker")
  else
    log("[SB2_TEST_Q2] CHUNKED_WSP: chunk1 simulation write failed: " .. tostring(sim_err_1))
  end

  -- Simulujeme crash: NEZAPISUJEME chunk2 (ostane stara hodnota alebo predosla)
  local sim_crash_ok, sim_crash_err = pcall(function()
    error("sb2_simulated_chunk_crash")
  end)
  -- sim_crash_ok = false, chunk2 nebol prepisany
  log("[SB2_TEST_Q2] CHUNKED_WSP: crash simulated. chunk1=CRASH_SIMULATION_VALUE, chunk2=previous value")
  log("[SB2_TEST_Q2] CHUNKED_WSP: Reload save, then call sb2TestAtomicWrite.checkChunksAfterReload() to verify partial persistence")
end

-- --- Cleanup chunkov ---
local function _cleanupChunks()
  log("[SB2_TEST_Q2] ----------------------------------------")
  log("[SB2_TEST_Q2] Cleanup: removing chunk properties")

  local keys = {SB2_CHUNK_KEY_1, SB2_CHUNK_KEY_2}
  for _, key in ipairs(keys) do
    local ok, err = pcall(function() world.setProperty(key, nil) end)
    if ok then
      log("[SB2_TEST_Q2] CLEANUP: " .. key .. " via nil")
    else
      local ok2, err2 = pcall(function() world.setProperty(key, "") end)
      if ok2 then
        log("[SB2_TEST_Q2] CLEANUP: " .. key .. " via empty-string (nil failed: " .. tostring(err) .. ")")
      else
        log("[SB2_TEST_Q2] CLEANUP: " .. key .. " FAILED both methods")
      end
    end
  end

  log("[SB2_TEST_Q2] CLEANUP: For " .. SB2_TMP_FILE .. " – delete manually: rm " .. SB2_TMP_FILE)
end

-- PUBLIC: Spusti vsetky Q2 sub-testy a vypise zaverecnu tabulku.
-- Side effects: Zapisuje world.properties, moze vytvorit /tmp/sb2_test_atomic.txt
-- stable API: nie (disposable prototype)
function sb2TestAtomicWrite.runAll()
  log("[SB2_TEST_Q2] ========================================")
  log("[SB2_TEST_Q2] Q2 Atomic Write Methods – full test run")
  log("[SB2_TEST_Q2] ========================================")

  -- Zbierame vysledky pre zaverecnu tabulku
  local verdict_asset = "unavailable"
  local verdict_io = "unavailable"
  local verdict_chunked = "unknown"

  -- Sub-test 1: assetJson
  local asset_write_ok = false
  do
    -- Presmerovanie cez pcall aby sub-test nepadol cely runAll
    local ok, err = pcall(_runAssetJsonProbe)
    if not ok then
      log("[SB2_TEST_Q2] Sub-test 1 internal error: " .. tostring(err))
      verdict_asset = "internal_error"
    else
      -- Verdikt rekonstruujeme z logu – tu jednoducho reportujeme ze prebehol
      verdict_asset = "see log above"
    end
  end

  -- Sub-test 2: io.*
  local io_available = false
  do
    local ok, result = pcall(_runIoSandboxProbe)
    if not ok then
      log("[SB2_TEST_Q2] Sub-test 2 internal error: " .. tostring(result))
      verdict_io = "internal_error"
    elseif result == true then
      verdict_io = "available (io.open works)"
      io_available = true
    else
      verdict_io = "blocked (io table nil or io.open fails)"
    end
  end

  -- Sub-test 3: chunked WSP
  do
    local ok, err = pcall(_runChunkedWspTest)
    if not ok then
      log("[SB2_TEST_Q2] Sub-test 3 internal error: " .. tostring(err))
      verdict_chunked = "internal_error"
    else
      verdict_chunked = "see log above (PASS/FAIL per line)"
    end
  end

  -- Cleanup
  _cleanupChunks()

  -- Zaverecna tabulka
  log("[SB2_TEST_Q2] ========================================")
  log("[SB2_TEST_Q2] atomic write methods comparison")
  log("[SB2_TEST_Q2]  (a) root.assetJson write : " .. verdict_asset)
  log("[SB2_TEST_Q2]  (b) io.* sandbox         : " .. verdict_io)
  log("[SB2_TEST_Q2]  (c) chunked setProperty  : " .. verdict_chunked)

  -- Odporucanie na zaklade vysledkov
  local recommendation
  if io_available then
    recommendation = "io.* is available. Use io.open + atomic write pattern (write to .tmp, rename to final). Best for universe-level state."
  else
    recommendation = "io.* is blocked. Use chunked world.setProperty if per-world state is sufficient. For universe-level state: investigate placeholder world approach or world.setProperty on ship world."
  end

  log("[SB2_TEST_Q2] RECOMMENDATION: " .. recommendation)
  log("[SB2_TEST_Q2] ========================================")
  log("[SB2_TEST_Q2] runAll COMPLETE. Check starbound.log for full results.")
  if io_available then
    log("[SB2_TEST_Q2] NOTE: Verify " .. SB2_TMP_FILE .. " manually after test.")
    log("[SB2_TEST_Q2] Cleanup: rm " .. SB2_TMP_FILE)
  end
  log("[SB2_TEST_Q2] ========================================")
end

-- PUBLIC: Overi stav chunkov po reloade save (po crash-mid-write simulacii).
-- Ocakavany volanie: reload save, potom zavolaj tuto funkciu.
-- stable API: nie (disposable prototype)
function sb2TestAtomicWrite.checkChunksAfterReload()
  log("[SB2_TEST_Q2] ========================================")
  log("[SB2_TEST_Q2] checkChunksAfterReload: verifying partial persistence after simulated crash")

  local r1_ok, r1_val = pcall(function() return world.getProperty(SB2_CHUNK_KEY_1) end)
  local r2_ok, r2_val = pcall(function() return world.getProperty(SB2_CHUNK_KEY_2) end)

  -- Chunk 1 mohol byt zapovednany nastavenim na CRASH_SIMULATION_VALUE pred crashom
  if not r1_ok then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk1 read error: " .. tostring(r1_val))
  elseif r1_val == nil then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk1 = nil (not persisted)")
  elseif r1_val == "CRASH_SIMULATION_VALUE" then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk1 = CRASH_SIMULATION_VALUE (persisted – partial write survived reload)")
  else
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk1 = '" .. string.sub(tostring(r1_val), 1, 80) .. "...' (other value)")
  end

  -- Chunk 2 nemal byt prepísaný po simulated crash
  if not r2_ok then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk2 read error: " .. tostring(r2_val))
  elseif r2_val == nil then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk2 = nil")
  elseif r2_val == "" then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk2 = empty string")
  else
    local chunk2_preview = string.sub(tostring(r2_val), 1, 40)
    log("[SB2_TEST_Q2] CHUNK_RELOAD: chunk2 = '" .. chunk2_preview .. "...' (len=" .. #tostring(r2_val) .. ")")
  end

  -- Verdikt
  local chunk1_persisted = r1_ok and r1_val ~= nil and r1_val ~= ""
  local chunk2_old_value = r2_ok and r2_val ~= nil and r2_val ~= ""

  if chunk1_persisted and chunk2_old_value then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: CONFIRMED partial persistence – chunk1 has new value, chunk2 has old value")
    log("[SB2_TEST_Q2] CHUNK_RELOAD: world.setProperty is NOT atomic across multiple keys (expected)")
  elseif not chunk1_persisted and not chunk2_old_value then
    log("[SB2_TEST_Q2] CHUNK_RELOAD: both chunks are empty/nil – world properties may not persist across reload in this world type")
  else
    log("[SB2_TEST_Q2] CHUNK_RELOAD: mixed state – see individual chunk values above")
  end

  -- Cleanup po overeni
  _cleanupChunks()

  log("[SB2_TEST_Q2] checkChunksAfterReload COMPLETE.")
  log("[SB2_TEST_Q2] ========================================")
end
