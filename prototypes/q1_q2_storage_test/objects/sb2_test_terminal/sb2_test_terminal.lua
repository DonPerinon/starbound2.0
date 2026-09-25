-- sb2_test_terminal.lua
-- ScriptPane callback handler pre SB2 Q1/Q2 Storage Test Terminal.
-- Deleguje vsetky volania na sb2_test_world_property.lua a sb2_test_atomic_write.lua.
-- Used by: ScriptPane (interactAction v sb2_test_terminal.object)
-- Performance: event-driven (nie per-tick), spusti sa len pri kliknuti tlacidla

-- Vsetky sb2_test_* kluce ktore tento mod moze vytvarat
local SB2_ALL_TEST_KEYS = {
  "sb2_test_prop_1kb",
  "sb2_test_prop_10kb",
  "sb2_test_prop_50kb",
  "sb2_test_prop_100kb",
  "sb2_test_prop_250kb",
  "sb2_test_prop_500kb",
  "sb2_test_prop_1024kb",
  "sb2_test_prop_5120kb",
  "sb2_test_nil_behavior",
  "sb2_test_xworld_marker",
  "sb2_test_univ_chunk_1",
  "sb2_test_univ_chunk_2",
  "sb2_test_already_run"
}

-- Interne: aktualizuje status label. Nepadne ak widget nedostupny.
local function _setStatus(msg)
  local ok, err = pcall(function()
    widget.setText("statusLabel", msg)
  end)
  if not ok then
    sb.logInfo("[SB2_TERMINAL] widget.setText failed: " .. tostring(err))
  end
end

-- Interne: bezpecne require modulu. Vracia nacitany modul alebo nil pri chybe.
-- Starbound require pouziva asset-root absolutne cesty.
local function _safeRequire(path)
  local ok, mod = pcall(require, path)
  if not ok then
    sb.logInfo("[SB2_TERMINAL] require failed for '" .. path .. "': " .. tostring(mod))
    return nil
  end
  -- Niektoré Starbound require implementácie vrátia true namiesto tabulky,
  -- ak modul pouziva globals namiesto return. Skontrolujeme global namespace.
  return mod
end

-- Interne: vola funkciu z globálnej tabulky s pcall, vracia "PASS"/"FAIL"/"SEE LOG"
local function _callGlobal(tbl_name, fn_name)
  local tbl = _G[tbl_name]
  if tbl == nil then
    sb.logInfo("[SB2_TERMINAL] global table '" .. tbl_name .. "' not found – require may have failed")
    return "FAIL"
  end
  local fn = tbl[fn_name]
  if type(fn) ~= "function" then
    sb.logInfo("[SB2_TERMINAL] '" .. tbl_name .. "." .. fn_name .. "' is not a function")
    return "FAIL"
  end
  local ok, err = pcall(fn)
  if ok then
    return "SEE LOG"
  else
    sb.logInfo("[SB2_TERMINAL] ERROR in " .. tbl_name .. "." .. fn_name .. ": " .. tostring(err))
    return "FAIL"
  end
end

-- init: zavolany pri otvoreni pane
function init()
  _setStatus("Status: READY")
end

-- PUBLIC CALLBACK: Q1 – size sweep + LOGTRUNC probe
function button1()
  _setStatus("Status: Running Q1 size sweep...")
  _safeRequire("/scripts/sb2_test_world_property.lua")
  local result = _callGlobal("sb2TestWorldProperty", "runSizeTest")
  _setStatus("Status: Q1 size sweep done -> " .. result)
end

-- PUBLIC CALLBACK: Q1 X-world krok 1 – zapis marker na aktualnom svete
function button2()
  _setStatus("Status: Writing X-world marker HERE...")
  _safeRequire("/scripts/sb2_test_world_property.lua")
  local result = _callGlobal("sb2TestWorldProperty", "crossWorldStep1Write")
  _setStatus("Status: X-world write done -> " .. result .. " (warp to other world)")
end

-- PUBLIC CALLBACK: Q1 X-world krok 2 – citanie markera po warpe
function button3()
  _setStatus("Status: Reading X-world marker (after warp)...")
  _safeRequire("/scripts/sb2_test_world_property.lua")
  local result = _callGlobal("sb2TestWorldProperty", "crossWorldStep2Read")
  _setStatus("Status: X-world read done -> " .. result)
end

-- PUBLIC CALLBACK: Q1 X-world krok 3 – prepis markera
function button4()
  _setStatus("Status: Overwriting X-world marker...")
  _safeRequire("/scripts/sb2_test_world_property.lua")
  local result = _callGlobal("sb2TestWorldProperty", "crossWorldStep3Overwrite")
  _setStatus("Status: X-world overwrite done -> " .. result .. " (warp back to A)")
end

-- PUBLIC CALLBACK: Q1 X-world krok 4 – verifikacia po warpnuti spat
function button5()
  _setStatus("Status: Verifying X-world marker (back on world A)...")
  _safeRequire("/scripts/sb2_test_world_property.lua")
  local result = _callGlobal("sb2TestWorldProperty", "crossWorldStep4Verify")
  _setStatus("Status: X-world verify done -> " .. result)
end

-- PUBLIC CALLBACK: Q2 – vsetky atomic write testy
function button6()
  _setStatus("Status: Running Q2 atomic write tests...")
  _safeRequire("/scripts/sb2_test_atomic_write.lua")
  local result = _callGlobal("sb2TestAtomicWrite", "runAll")
  _setStatus("Status: Q2 runAll done -> " .. result)
end

-- PUBLIC CALLBACK: Q2 – overenie chunkov po reloade save
function button7()
  _setStatus("Status: Checking chunks after reload...")
  _safeRequire("/scripts/sb2_test_atomic_write.lua")
  local result = _callGlobal("sb2TestAtomicWrite", "checkChunksAfterReload")
  _setStatus("Status: Q2 chunk reload check done -> " .. result)
end

-- PUBLIC CALLBACK: vymaz vsetky sb2_test_* world properties
function button8()
  _setStatus("Status: Cleaning up all sb2_test_* keys...")
  sb.logInfo("[SB2_TERMINAL] button8: starting cleanup of all sb2_test_* world properties")

  local cleaned = 0
  local failed = 0

  for _, key in ipairs(SB2_ALL_TEST_KEYS) do
    -- Pokus cez nil (maze kluc)
    local ok, err = pcall(function()
      world.setProperty(key, nil)
    end)
    if ok then
      sb.logInfo("[SB2_TERMINAL] CLEANUP: " .. key .. " via nil")
      cleaned = cleaned + 1
    else
      -- Fallback: prazdny string
      local ok2, err2 = pcall(function()
        world.setProperty(key, "")
      end)
      if ok2 then
        sb.logInfo("[SB2_TERMINAL] CLEANUP: " .. key .. " via empty-string (nil failed: " .. tostring(err) .. ")")
        cleaned = cleaned + 1
      else
        sb.logInfo("[SB2_TERMINAL] CLEANUP FAILED: " .. key .. " (both nil and empty-string failed)")
        failed = failed + 1
      end
    end
  end

  local summary = "cleaned=" .. cleaned .. " failed=" .. failed
  sb.logInfo("[SB2_TERMINAL] button8: cleanup done. " .. summary)
  _setStatus("Status: Cleanup done. " .. summary)
end
