-- objects/sb2_market/sb2_market_pane.lua
-- Klientsky ScriptPane skript terminalu sb2_market (economy-system.md 5.4).
-- Pyta si riadky od objektu (server) cez entity message, filtruje a formatuje
-- ich cez sb2_market_view. Read-only, ziadny obchod.
-- Used by: sb2_market_pane.config
-- Performance: update() iba polluje jeden RpcPromise, inak nic
-- Lua 5.1 striktne.

require("/scripts/sb2_util.lua")
require("/scripts/sb2_config.lua")
require("/scripts/sb2_market_view.lua")

local REASONS_CONFIG = "/configs/sb2_economy_reasons.config"

local ui = nil            -- parametre z pane configu (sekcia "sb2")
local pending = nil       -- RpcPromise cakajuci na odpoved objektu
local pending_kind = nil  -- "breakdown" | "seed"
local all_rows = {}
local shown_rows = {}
local filter_category = "all"
local changed_only = false
local reason_labels = {}

local function log(msg)
  sb.logInfo("[SB2_MARKET_PANE] " .. msg)
end

local function setText(name, text)
  local ok, err = pcall(widget.setText, name, text)
  if not ok then log("setText " .. name .. " failed: " .. tostring(err)) end
end

local function requestBreakdown()
  local entity = pane.sourceEntity()
  pending = world.sendEntityMessage(entity, "sb2_market.getBreakdown")
  pending_kind = "breakdown"
  setText("statusLabel", ui.text.loading)
end

local function render()
  shown_rows = sb2_market_view.filterRows(all_rows, filter_category, changed_only)
  widget.clearListItems("scrollArea.rowList")
  for i = 1, #shown_rows do
    local item = widget.addListItem("scrollArea.rowList")
    widget.setText("scrollArea.rowList." .. item .. ".label",
      sb2_market_view.formatRow(shown_rows[i], ui.rowFormat, ui.itemWidth))
  end
  setText("reasonLabel", ui.text.selectHint)
end

local function onBreakdown(result)
  if type(result) ~= "table" then
    setText("statusLabel", ui.text.error)
    return
  end
  if result.ok ~= true then
    all_rows = {}
    render()
    if result.reason == "no_state" then
      setText("statusLabel", ui.text.noState)
    else
      setText("statusLabel", ui.text.error)
      log("breakdown error: " .. tostring(result.detail))
    end
    return
  end
  all_rows = result.rows or {}
  render()
  setText("statusLabel", string.format(ui.text.stationDay,
    result.station_id, result.day_index, result.last_recompute_day, #all_rows))
end

function init()
  ui = config.getParameter("sb2")
  sb2_util.require(type(ui) == "table", "sb2_market_pane: missing 'sb2' section in pane config")
  local reasons_cfg = sb2_config.load(REASONS_CONFIG)
  reason_labels = reasons_cfg.labels or {}

  setText("headerLabel", string.format(ui.headerFormat,
    ui.headerColumns[1], ui.headerColumns[2], ui.headerColumns[3], ui.headerColumns[4],
    ui.headerColumns[5], ui.headerColumns[6], ui.headerColumns[7], ui.headerColumns[8]))
  setText("formulaLabel", ui.formulaText)
  setText("changedToggle", ui.text.changedOff)

  local is_admin = false
  pcall(function() is_admin = player.isAdmin() end)
  pcall(widget.setVisible, "seedButton", is_admin)

  requestBreakdown()
end

function update(dt)
  if pending == nil then return end
  if not pending:finished() then return end
  local promise, kind = pending, pending_kind
  pending, pending_kind = nil, nil
  if not promise:succeeded() then
    setText("statusLabel", ui.text.error)
    log("entity message failed: " .. tostring(promise:error()))
    return
  end
  if kind == "breakdown" then
    onBreakdown(promise:result())
  elseif kind == "seed" then
    local result = promise:result()
    if type(result) == "table" and result.ok then
      setText("statusLabel", ui.text.seeded)
      requestBreakdown()
    else
      setText("statusLabel", ui.text.error)
    end
  end
end

-- Internal: nastavi filter kategorie a prekresli
local function setFilter(category)
  filter_category = category
  render()
end

-- PUBLIC CALLBACKS (widget callbacks z pane configu)
function filterAll()   setFilter("all") end
function filterOre()   setFilter("ore") end
function filterFood()  setFilter("food") end
function filterFuel()  setFilter("fuel") end
function filterMetal() setFilter("refined_metal") end
function filterMed()   setFilter("medicine") end
function filterAdv()   setFilter("advanced_component") end

function toggleChanged()
  changed_only = not changed_only
  setText("changedToggle", changed_only and ui.text.changedOn or ui.text.changedOff)
  render()
end

function refresh()
  if pending == nil then requestBreakdown() end
end

function seedDemo()
  if pending ~= nil then return end
  pending = world.sendEntityMessage(pane.sourceEntity(), "sb2_market.seedDemo")
  pending_kind = "seed"
  setText("statusLabel", ui.text.loading)
end

function rowSelected()
  local selected = widget.getListSelected("scrollArea.rowList")
  if selected == nil then return end
  -- list vracia nazov polozky; index zistime porovnanim s poradim pridania
  local index = nil
  local ok = pcall(function() index = tonumber(widget.getData("scrollArea.rowList." .. selected)) end)
  if not ok or index == nil then
    -- fallback: Starbound list itemy su cislovane od 0 v poradi pridania
    index = tonumber(string.match(selected, "(%d+)$"))
    if index ~= nil then index = index + 1 end
  end
  local row = index and shown_rows[index] or nil
  if row == nil then return end
  local lines = sb2_market_view.reasonLines(row.top_reasons, reason_labels, ui.reasonFormat)
  if #lines == 0 then
    setText("reasonLabel", row.item .. ": -")
  else
    setText("reasonLabel", row.item .. ": " .. table.concat(lines, "  |  "))
  end
end
