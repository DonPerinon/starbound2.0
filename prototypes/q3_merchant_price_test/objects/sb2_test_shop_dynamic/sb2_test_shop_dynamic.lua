-- sb2_test_shop_dynamic.lua
-- Prototype Q3b/Q3c: merchant config sa sklada v Lua pri kazdom otvoreni.
-- Kazde otvorenie zvysi pocitadlo v storage a ceny sa posunu o +10 % za otvorenie,
-- aby bolo v hre okamzite vidiet, ci merchant pane berie ceny z Lua.
-- Used by: sb2_test_shop_dynamic.object (onInteraction)
-- Performance: one-time per interakcia (nie hot path)
-- Lua 5.1 striktne – ziadne goto, ziadne //, ziadne bitwise operatory

local BASE_PRICES = {
  { item = "liquidwater",  base = 5 },
  { item = "titaniumbar",  base = 12 },
  { item = "corefragment", base = 30 }
}

local function log(msg)
  sb.logInfo("[SB2_TEST_Q3] " .. msg)
end

function init()
  object.setInteractive(true)
  storage.open_count = storage.open_count or 0
  log("dynamic shop init, open_count = " .. tostring(storage.open_count))
end

-- Internal: zostavi jeden riadok merchant item listu
local function _buildItemEntry(item_name, base_price, multiplier)
  local final_price = math.floor(base_price * multiplier + 0.5)
  local pct = math.floor((multiplier - 1.0) * 100 + 0.5)
  local reason = string.format("SB2 dynamic: base %d, otvorenie #%d, %+d%%",
    base_price, storage.open_count, pct)
  return {
    item = {
      name = item_name,
      count = 1,
      parameters = {
        description = reason
      }
    },
    price = final_price
  }
end

-- Volane enginom pri interakcii hraca s objektom.
-- Navratova hodnota { "OpenMerchantInterface", config } otvori merchant pane.
function onInteraction(args)
  storage.open_count = storage.open_count + 1
  local multiplier = 1.0 + 0.1 * storage.open_count

  local items = {}
  for i = 1, #BASE_PRICES do
    local entry = BASE_PRICES[i]
    items[#items + 1] = _buildItemEntry(entry.item, entry.base, multiplier)
    log(string.format("open #%d: %s base=%d -> price=%d",
      storage.open_count, entry.item, entry.base, items[#items].price))
  end

  local merchant_config = {
    config = "/interface/windowconfig/merchant.config",
    buyFactor = 1.0,
    sellFactor = 0.2,
    items = items
  }

  return { "OpenMerchantInterface", merchant_config }
end
