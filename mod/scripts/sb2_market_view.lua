-- mod/scripts/sb2_market_view.lua
-- Prezentacna logika breakdown panelu sb2_market (economy-system.md 5.4):
-- filter podla kategorie / len zmenene dnes, formatovanie riadkov, texty dovodov.
-- Cisty modul – ziadne widget/world API, testovatelny mimo hry.
-- Used by: objects/sb2_market/sb2_market_pane.lua
-- Performance: cold path (pri otvoreni panelu a zmene filtra)
-- Lua 5.1 striktne.

-- Internal: nacita zavislost v Starbounde (asset cesta, modul sa registruje ako
-- global) aj v standalone Lua (package.path, modul vracia tabulku).
local function sb2_load(name)
  if _G[name] ~= nil then return _G[name] end
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then return mod end
  require("/scripts/" .. name .. ".lua")
  return _G[name]
end

local sb2_util = sb2_load("sb2_util")

local sb2_market_view = {}

-- Public API (stable)
-- rows: vystup sb2_market_state.breakdownRows. category: string alebo "all".
-- changed_only: true = iba riadky s delta_pct ~= 0.
function sb2_market_view.filterRows(rows, category, changed_only)
  local out = {}
  for i = 1, #rows do
    local row = rows[i]
    local cat_ok = (category == nil or category == "all" or row.category == category)
    local chg_ok = (not changed_only) or (row.delta_pct ~= 0)
    if cat_ok and chg_ok then
      out[#out + 1] = row
    end
  end
  return out
end

-- Public API (stable)
-- Zoznam kategorii pritomnych v riadkoch (zoradeny), pre filter tlacidla.
function sb2_market_view.categories(rows)
  local seen = {}
  for i = 1, #rows do
    if rows[i].category then seen[rows[i].category] = true end
  end
  return sb2_util.sortedKeys(seen)
end

-- Public API (stable)
-- Jeden riadok tabulky podla formatu z pane configu.
-- fmt ma 8 miest: item, base, M_local, A_regional, M_global, tlak %, final, delta %
function sb2_market_view.formatRow(row, fmt, item_width)
  item_width = item_width or 14
  local name = row.item
  if #name > item_width then
    name = string.sub(name, 1, item_width - 1) .. "~"
  end
  return string.format(fmt,
    name, row.base, row.m_local, row.a_regional, row.m_global,
    sb2_util.round(row.p_pressure * 100), row.final, row.delta_pct)
end

-- Public API (stable)
-- Text dovodov pre vybrany riadok: "+30% Blokada Apexov" per riadok.
-- labels: mapa label -> zobrazeny text (sb2_economy_reasons.config), chybajuci
-- label sa zobrazi ako surovy kluc (vidno, ze chyba preklad, nie ticho).
function sb2_market_view.reasonLines(top_reasons, labels, line_fmt)
  line_fmt = line_fmt or "%+d%% %s"
  local lines = {}
  for i = 1, #(top_reasons or {}) do
    local reason = top_reasons[i]
    local text = labels[reason.label]
    if text == nil then
      -- label moze mat dynamicky suffix (blockade_apex): skus prefix pred poslednym '_'
      local prefix, suffix = string.match(reason.label, "^(.-)_([^_]+)$")
      if prefix and labels[prefix] then
        text = labels[prefix] .. " " .. suffix
      else
        text = reason.label
      end
    end
    lines[#lines + 1] = string.format(line_fmt, reason.delta_pct, text)
  end
  return lines
end

_G["sb2_market_view"] = sb2_market_view
return sb2_market_view
