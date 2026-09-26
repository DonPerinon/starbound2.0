-- mod/scripts/sb2_station.lua
-- Identita stanice pre DPS/FIS. v0.1 rozhodnutie: jedna stanica = jeden svet,
-- station_id je explicitny parameter objektu/NPC alebo sanitizovane world.id().
-- Used by: sb2_market objekt, merchant hook (neskor), FIS
-- Performance: one-time per interakcia
-- Lua 5.1 striktne.

local sb2_station = {}

-- Public API (stable)
-- Vrati station_id: explicit (ak je neprazdny string) alebo odvodeny z world_id.
-- Dvojbodky a ine znaky mimo [A-Za-z0-9_-] sa nahradia podciarkovnikom,
-- aby bol kluc property bezpecny a citatelny v logu.
function sb2_station.resolveStationId(explicit, world_id)
  if type(explicit) == "string" and #explicit > 0 then
    return sb2_station.sanitize(explicit)
  end
  if type(world_id) == "string" and #world_id > 0 then
    return sb2_station.sanitize(world_id)
  end
  error("[SB2] resolveStationId: neither explicit id nor world id available")
end

-- Public API (stable)
function sb2_station.sanitize(id)
  local out = string.gsub(id, "[^%w_%-]", "_")
  return out
end

-- Public API (stable)
-- Kluc systemu z celestial suradnic (influence-system.md 4.3).
function sb2_station.systemKey(world_coords)
  if type(world_coords) ~= "table" or #world_coords < 3 then
    return "system_unknown"
  end
  return string.format("system_%d_%d_%d", world_coords[1], world_coords[2], world_coords[3])
end

_G["sb2_station"] = sb2_station
return sb2_station
