-- mod/scripts/sb2_economy_tags.lua
-- Taxonomia itemov pre DPS (docs/economy-system.md sekcia 4.3).
-- Rozhoduje, ci je item tracked, do akej kategorie patri a ake ma parametre.
-- Used by: sb2_market_state (pri prvom pridani itemu), sb2_economy_init (drift scan)
-- Performance: cold path (jedno volanie per item pri init / prvom obchode)
-- Lua 5.1 striktne.

local sb2_util = require("sb2_util")

local sb2_economy_tags = {}

-- Internal: je hodnota v zozname?
local function _contains(list, value)
  for i = 1, #list do
    if list[i] == value then return true end
  end
  return false
end

-- Public API (stable)
-- Overi strukturu tags configu. Crash pri chybe (no silent failures).
function sb2_economy_tags.validate(tags_config)
  sb2_util.require(type(tags_config) == "table", "tags config must be a table")
  sb2_util.require(tags_config.schema_version == 1, "tags config schema_version must be 1")
  sb2_util.require(type(tags_config.tracked_fu_tags) == "table", "tags config missing tracked_fu_tags")
  sb2_util.require(type(tags_config.category_defaults) == "table", "tags config missing category_defaults")
  for i = 1, #tags_config.tracked_fu_tags do
    local tag = tags_config.tracked_fu_tags[i]
    sb2_util.require(tags_config.category_defaults[tag] ~= nil,
      "tracked tag '" .. tostring(tag) .. "' has no category_defaults entry")
  end
  tags_config.item_overrides = tags_config.item_overrides or {}
  return true
end

-- Public API (stable)
-- Vrati kategoriu itemu alebo nil, ak item nie je tracked.
-- item_tags: zoznam tagov itemu (z item configu), item_name: id itemu.
-- Pravidlo coverage (4.3): sb2_static override > sb2_dynamic / tracked tag > item_overrides.category.
function sb2_economy_tags.resolveCategory(item_name, item_tags, tags_config)
  item_tags = item_tags or {}
  local opt_out = tags_config.opt_out_override_tag or "sb2_static"
  local opt_in = tags_config.opt_in_override_tag or "sb2_dynamic"

  if _contains(item_tags, opt_out) then
    return nil
  end

  local override = tags_config.item_overrides[item_name]
  if override and override.category then
    return override.category
  end

  -- prvy tracked tag v poradi tracked_fu_tags rozhoduje o kategorii
  for i = 1, #tags_config.tracked_fu_tags do
    local tag = tags_config.tracked_fu_tags[i]
    if _contains(item_tags, tag) then
      return tag
    end
  end

  if _contains(item_tags, opt_in) then
    -- opt-in bez znamej kategorie: fallback na prvu kategoriu s defaultmi
    return tags_config.tracked_fu_tags[1]
  end

  return nil
end

-- Public API (stable)
-- Parametre itemu: category_defaults prekryte item_overrides.
-- Vrati { category, daily_turnover_baseline, decay_factor, jitter_amplitude }.
function sb2_economy_tags.getItemParams(item_name, category, tags_config, economy_config)
  local defaults = tags_config.category_defaults[category]
  sb2_util.require(defaults ~= nil, "unknown category '" .. tostring(category) .. "' for item " .. tostring(item_name))
  local override = tags_config.item_overrides[item_name] or {}
  return {
    category = category,
    daily_turnover_baseline = override.daily_turnover_baseline
      or defaults.daily_turnover_baseline
      or economy_config.default_daily_turnover_baseline,
    decay_factor = override.decay_factor
      or defaults.decay_factor
      or economy_config.default_decay_factor,
    jitter_amplitude = override.jitter_amplitude
      or defaults.jitter_amplitude
      or economy_config.default_jitter_amplitude
  }
end

-- Public API (stable)
-- Drift scan (6.4): pre vzorku itemov z item_overrides overi, ci ich aktualne tagy
-- stale obsahuju ocakavanu kategoriu. resolve_tags(item_name) -> zoznam tagov.
-- Vrati { checked = N, mismatched = { item_name, ... }, drift = bool }.
function sb2_economy_tags.scanTaxonomyDrift(tags_config, resolve_tags, max_sample)
  max_sample = max_sample or 20
  local result = { checked = 0, mismatched = {}, drift = false }
  local names = sb2_util.sortedKeys(tags_config.item_overrides)
  for i = 1, math.min(#names, max_sample) do
    local name = names[i]
    local expected = tags_config.item_overrides[name].category
    if expected then
      local tags = resolve_tags(name)
      result.checked = result.checked + 1
      if tags == nil or not _contains(tags, expected) then
        result.mismatched[#result.mismatched + 1] = name
      end
    end
  end
  if result.checked > 0 and (#result.mismatched / result.checked) > 0.2 then
    result.drift = true
  end
  return result
end

return sb2_economy_tags
