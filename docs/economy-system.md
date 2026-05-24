# Dynamic Pricing System – Design Document

## Out of scope of this document

Tento dokument pokrýva výpočet a perzistenciu cien. Nasledujúce súvisiace oblasti sú vyčlenené do samostatných sub-design dokumentov a budú vznikať postupne:

- **`docs/trade-flow-v01.md`** – scheduler konvojov (kto, kedy, čo, kam posiela), generačné pravidlá `trade_flows` záznamov. Tento doc iba konzumuje výsledný modifikátor.
- **`docs/economy-ui.md`** – detailný UI layout pre tooltip extension a breakdown panel. Tento doc definuje iba dátový kontrakt (`top_reasons`, schema), nie pixel-level layout.
- **`docs/COMPATIBILITY_TESTING.md`** – manuálny smoke test checklist po FU update. Tento doc obsahuje iba minimálnu inline verziu v sekcii 9.3.

Sub-design docs vzniknú až keď príslušnú oblasť reálne implementujeme, nie dopredu.

## 1. Cieľ systému

Dynamic Pricing System (ďalej DPS) je prvý funkčný systém Starbound 2.0 a tvorí jadro pillaru **Living Economy**. Pretvára statické ceny FU/vanilla merchantov na dynamický stav, ktorý reaguje na:

- lokálnu ponuku a dopyt na úrovni jednej stanice / planéty (per-station market),
- abstraktné trade flow modifikátory medzi staničkami (konvoje ako data records),
- frakčné a regionálne udalosti (blokády, vojny, prebytky) ako modifikátory zhora,
- akcie hráča (logaritmicky škálované podľa podielu z denného obratu).

**Tvrdé požiadavky (zo success criteria vízie):**

- Cena minimálne jednej sledovanej komodity sa za 5 herných dní pohne o ≥30 % bez priameho hráčskeho zásahu.
- Každá dynamická cena má v UI viditeľný dôvod (top 3 modifikátory s ± %).
- Per-tick logika neprekročí 1 ms na entity.
- No silent data corruption – pri každom risky kroku backup do `*.bak`.
- Schema versioning prítomné od dňa 1 v každom perzistent state súbore.
- Co-op deterministic: dvaja klienti v rovnakej session vidia rovnaké ceny pre rovnakú stanicu v rovnakom dni.

**Nie je cieľom v0.1:**

- vizuálne simulované konvoje (entity NPC lode) – iba abstraktné data records,
- AI ktorá píše do ekonomického stavu (v0.1 read-only),
- FU faction shops, Infinity Express, SAIL shop (v0.5+),
- prepisanie FU cien (v0.1 iba vanilla NPC merchanti + FU `terramart`).

## 2. Hlavné mechaniky

### 2.1 Event-driven recalculation s lazy fallback

DPS neprepočítava každú cenu každý tick. Cena sa prepočíta v jednom z troch momentov:

1. **Lazy on-read** – keď merchant otvorí inventár (hráč klikol na NPC) a posledný recompute pre danú položku je starší ako prahová doba (`recompute_max_age_ticks`, default = 1 day tick).
2. **Event-driven push** – keď nastane udalosť, ktorá by mala vyvolať skok (blokáda začala, hráč predal veľkú zásobu, konvoj dorazil). Eventy sa zapisujú do `pending_events` per market a aplikujú sa pri najbližšom recompute.
3. **Heartbeat day-tick** – periodický `sb2_economy_day` tick (default 30 min realtime, konfigurovateľný), ktorý:
   - posunie `day_index` o 1,
   - resetuje `daily_turnover` pre všetky aktívne markety,
   - aplikuje decay/mean reversion na všetky modifikátory,
   - generuje deterministický jitter event per market (PRNG seedovaný `(world_seed, station_id, day_index)`).

### 2.2 Modifiers chain

Cena pre konkrétny item v konkrétnom markete sa skladá z reťazca modifikátorov, kategorizovaných do troch vrstiev:

1. **Local layer** (per-market) – `local_supply_demand_ratio`, `daily_player_pressure`, `station_specialization_bonus`.
2. **Regional layer** (per-system / per-region) – `trade_flow_modifier` (z abstraktných konvojov), `regional_event_modifier` (blokáda, vojna v systéme).
3. **Global layer** (universe-level) – `faction_global_modifier` (napr. Floran globálny hladomor), `seasonal_modifier` (rezervované pre v0.5+).

Modifikátory vo vrstve 1 a 3 sú **multiplikatívne** (sčítanie by viedlo k absurdným záporným cenám pri viacerých negatívnych eventoch). Modifikátory vo vrstve 2 sú **aditívne medzi sebou v rámci vrstvy**, ale **multiplikatívne** voči vrstvám 1 a 3 (zdôvodnenie v sekcii 3). Player pressure je samostatne aditívny offset po multiplikatívnej zložke – zámerne, aby malé hráčske akcie neboli prenásobené veľkými modifikátormi a ostali viditeľné.

### 2.3 Trade flow ako abstraktný modifikátor (v0.1)

Konvoj nie je entity. Konvoj je záznam:

```
{ source_station, dest_station, items, depart_day, arrive_day, magnitude }
```

V `sb2_economy_day` tick:
- ak `current_day == depart_day`, source dostane `-magnitude` impulz pre dané items,
- ak `current_day == arrive_day`, dest dostane `+magnitude` impulz pre dané items.

Konvoje pre v0.1 generuje jednoduchý scheduler (mimo scope tohto doc, pôjde do samostatného sub-design doc `docs/trade-flow-v01.md`).

### 2.4 AI × economy (v0.1)

Frakčná AI je v v0.1 **read-only** vzhľadom na economy state. Číta agregované metriky (napr. `faction_food_availability`) a aplikuje 1–2 rules (napr. `hunger > threshold → faction_aggression += 1`). Nepíše do `sb2_market_state`. Plný feedback loop (AI → economy → AI) je odložený na v0.5.

## 3. Konkrétne formuly

### 3.1 Notácia

- `base_price` – pôvodná FU/vanilla cena itemu (číslo, pixels).
- `M_local` – produkt multiplikatívnych local modifikátorov (číslo, 0.1–10.0).
- `M_global` – produkt multiplikatívnych global modifikátorov (číslo, 0.1–10.0).
- `A_regional` – súčet aditívnych regional modifikátorov (číslo, -0.5–+2.0; reprezentuje "+50 % blokáda" ako 0.5).
- `P_pressure` – flat player pressure offset (signed číslo, jednotky % z base, typicky -0.3 až +0.3).
- `final_price` – finálna cena vrátená merchantovi (číslo, pixels, vždy ≥ `min_price_floor`).

### 3.2 Base price calculation

```
regional_multiplier = 1.0 + A_regional
final_price_raw = base_price * M_local * regional_multiplier * M_global * (1.0 + P_pressure)
final_price = max(min_price_floor, min(max_price_ceiling, round(final_price_raw)))
```

`min_price_floor = base_price * 0.1` a `max_price_ceiling = base_price * 10.0` ako tvrdé clampy (konfigurovateľné v `sb2_economy.config`, default hodnoty). Clamp je zámerný – chráni pred runaway exponentami pri náhode kde sa zreťazí 5 negatívnych modifikátorov.

### 3.3 Modifier stacking – zdôvodnenie mixu

- **Local a global multiplikatívne**: ekonomicky reprezentujú "%-zmenu", ktoré sa skladá multiplikatívne (10 % nárast x 10 % nárast = 21 %, nie 20 %). Aditívne by viedli k záporným cenám pri viacerých negatívnych eventoch (napr. -60 % + -50 % = -110 %).
- **Regional aditívne medzi sebou, multiplikatívne voči ostatným**: regionálne eventy (blokáda, vojna) sa typicky kumulujú ako "ďalších 30 % navrch" – aditívne. Voči local/global ide o samostatnú vrstvu reality (lokálny trh vs makro kontext), čo opodstatňuje multiplikatívne kombinovanie.
- **Player pressure aditívne flat offset**: zámerný dizajn pre transparent depth. Ak hráč predá veľa, vidí `-12 %` v tooltipe priamo, nie ako derivát z multiplikatívnej kaskády. Žiadne aktívne udalosti to neprenásobia ďalej.

### 3.4 Logaritmický player impact

Player pressure pre daný item v danom dni:

```
share = transaction_volume / max(1, daily_turnover_baseline)
sign = -1 if sell else +1     -- predaj tlačí cenu dolu, nákup hore
P_delta = sign * impact_coefficient * log(1 + share * scale_factor)
P_pressure_new = clamp(P_pressure_old + P_delta, -player_pressure_cap, +player_pressure_cap)
```

Defaultné konštanty (v `sb2_economy.config`, balansovateľné cez playtest):

- `impact_coefficient = 0.15`
- `scale_factor = 10.0`
- `player_pressure_cap = 0.5` (max ±50 % cez čisto hráčsky tlak za 1 deň)
- `daily_turnover_baseline` per item per market – nastavený podľa kategórie (ore má vyšší baseline než medicine).

**Vlastnosti formuly:**

- Pre malú transakciu (`share = 0.01`): `P_delta ≈ 0.15 * log(1.1) ≈ 0.014` (1.4 %). Viditeľné v UI, žiadny exploit.
- Pre veľkú transakciu (`share = 1.0`): `P_delta ≈ 0.15 * log(11) ≈ 0.36` (clamp na 0.5). Žiadny exploit cez single mega-transakciu.
- Reset `P_pressure` a `daily_turnover` každý `sb2_economy_day` tick.

### 3.5 Decay / mean reversion

Každý `sb2_economy_day` tick aplikuje na všetky modifikátory:

```
modifier_new = base_value + (modifier_old - base_value) * decay_factor
```

kde `decay_factor = 0.85` (default), `base_value = 1.0` pre multiplikatívne, `0.0` pre aditívne. Modifikátor s aktívnym zdrojom (napr. trvajúca blokáda) má `decay_factor = 1.0` (neklesá kým event trvá). Po skončení eventu sa `decay_factor` vráti na 0.85.

### 3.6 Deterministický jitter

```
seed = hash(world_seed, station_id, day_index)
prng = sb2_prng_new(seed)
jitter = (prng:next() - 0.5) * jitter_amplitude    -- typicky ±0.05
```

Aplikuje sa ako aditívny shift na vybraný náhodný item per market per day. Co-op klienti so zhodnými inputmi dostanú identický jitter.

## 4. Dátové štruktúry (JSON schémy)

### 4.1 Per-station market state

Uložené ako serializovaný blob cez `world.setProperty("sb2_market_state_<station_id>", ...)`.

```json
{
  "schema_version": 1,
  "station_id": "outpost_terramart_01",
  "world_coords": [123, 456, 7],
  "last_recompute_day": 142,
  "day_index": 145,
  "daily_turnover": {
    "liquidwater": 320,
    "corefragment": 12,
    "titaniumbar": 8
  },
  "items": {
    "liquidwater": {
      "base_price": 5,
      "local_modifiers": {
        "supply_demand": 0.85,
        "station_specialization": 1.0
      },
      "regional_modifiers_cached": {
        "trade_flow": -0.05
      },
      "global_modifiers_cached": {
        "faction_event": 1.0
      },
      "player_pressure": -0.08,
      "last_final_price": 4,
      "top_reasons_cache": [
        { "label": "supply_demand", "delta_pct": -15 },
        { "label": "player_pressure", "delta_pct": -8 },
        { "label": "trade_flow", "delta_pct": -5 }
      ]
    },
    "corefragment": {
      "base_price": 30,
      "local_modifiers": { "supply_demand": 1.42, "station_specialization": 1.2 },
      "regional_modifiers_cached": { "trade_flow": 0.10, "regional_event": 0.30 },
      "global_modifiers_cached": { "faction_event": 1.0 },
      "player_pressure": 0.0,
      "last_final_price": 64,
      "top_reasons_cache": [
        { "label": "regional_blockade_apex", "delta_pct": 30 },
        { "label": "station_mining_specialty", "delta_pct": 20 },
        { "label": "supply_demand", "delta_pct": 42 }
      ]
    }
  },
  "pending_events": [
    { "type": "trade_flow_arrival", "item": "titaniumbar", "magnitude": 0.12, "day": 146 }
  ],
  "migration_history": [
    { "from": 0, "to": 1, "at_day": 0, "at_realtime_iso": "2026-05-24T18:00:00Z" }
  ]
}
```

### 4.2 Universe-level economy state

Uložené ako `storage/sb2_economy_global.json` v Starbound storage dir.

```json
{
  "schema_version": 1,
  "current_day": 145,
  "tick_realtime_seconds": 1800,
  "world_seed": "a3f9c2e1",
  "global_modifiers": {
    "faction_floran_hunger": 1.18,
    "faction_apex_blockade": 1.0
  },
  "regional_modifiers": {
    "system_alpha_centauri": {
      "blockade_apex": 0.30,
      "expires_day": 158
    }
  },
  "trade_flows": [
    {
      "id": "convoy_0001",
      "source_station": "outpost_terramart_01",
      "dest_station": "floran_market_03",
      "items": { "liquidwater": 200, "titaniumbar": 20 },
      "depart_day": 144,
      "arrive_day": 147,
      "magnitude": 0.12
    }
  ],
  "known_stations": [
    {
      "station_id": "outpost_terramart_01",
      "world_uuid": "InstanceWorld:outpost:-:-",
      "last_visited_day": 145
    }
  ],
  "migration_history": [
    { "from": 0, "to": 1, "at_day": 0, "at_realtime_iso": "2026-05-24T18:00:00Z" }
  ]
}
```

### 4.3 Item tag taxonómia

Uložené ako `mod/configs/sb2_economy_tags.config`.

```json
{
  "schema_version": 1,
  "tracked_fu_tags": [
    "ore", "food", "fuel", "refined_metal", "medicine", "advanced_component"
  ],
  "opt_in_override_tag": "sb2_dynamic",
  "opt_out_override_tag": "sb2_static",
  "category_defaults": {
    "ore": {
      "daily_turnover_baseline": 200,
      "decay_factor": 0.85,
      "jitter_amplitude": 0.05
    },
    "food": {
      "daily_turnover_baseline": 400,
      "decay_factor": 0.80,
      "jitter_amplitude": 0.08
    },
    "fuel": {
      "daily_turnover_baseline": 150,
      "decay_factor": 0.85,
      "jitter_amplitude": 0.05
    },
    "refined_metal": {
      "daily_turnover_baseline": 100,
      "decay_factor": 0.90,
      "jitter_amplitude": 0.04
    },
    "medicine": {
      "daily_turnover_baseline": 50,
      "decay_factor": 0.88,
      "jitter_amplitude": 0.06
    },
    "advanced_component": {
      "daily_turnover_baseline": 30,
      "decay_factor": 0.92,
      "jitter_amplitude": 0.03
    }
  },
  "item_overrides": {
    "liquidwater": { "category": "food", "daily_turnover_baseline": 600 },
    "corefragment": { "category": "ore", "daily_turnover_baseline": 80 },
    "titaniumbar": { "category": "refined_metal" }
  }
}
```

**Kalibrácia `daily_turnover_baseline`:**
- Definícia: priemerný počet jednotiek itemu, ktoré prejdú cez jednu typickú stanicu danej kategórie za jeden `sb2_economy_day` počas bežnej hry FU veterána.
- Účel: slúži ako menovateľ vo výpočte `share` v sekcii 3.4 (logaritmický player impact). Príliš nízky baseline → malá transakcia vyletí na cap. Príliš vysoký → veľká transakcia má nulový dopad.
- V0.1 hodnoty v `category_defaults` a `item_overrides` sú **educated guesses**. Definitívna kalibrácia prebehne cez 2–3 playtest sessions (viď otvorená otázka č. 5) – meriame skutočný turnover per item per stanica, hodnoty v `sb2_economy_tags.config` upravíme tak, aby typická 1-stack transakcia vyvolala 1–5 % shift, full inventory transakcia narazila na cap.
- Re-kalibrácia je content-only zmena (JSON), nie schema bump – nevyžaduje migráciu.

Pravidlo coverage:
- Item je tracked DPS, ak má aspoň jeden tag z `tracked_fu_tags` ALEBO má tag `sb2_dynamic`.
- Item je vyradený, ak má tag `sb2_static` (override má prednosť pred tag matchom).
- Item bez tagov a bez override → static FU cena, DPS ho neeviduje.

### 4.4 Migration schema framework

Migration je definovaná ako čistá funkcia `migrate_vN_to_vN+1(state) → state`. Registruje sa do tabuľky `sb2_migrations` per state typ. Migration runner:

```
function flow:
  load raw state from disk
  detect schema_version
  if schema_version < current_version:
    backup raw state to <path>.bak.v<schema_version>
    for v in (schema_version .. current_version - 1):
      state = sb2_migrations[state_type][v](state)
      append migration_history entry
    save migrated state
  if schema_version > current_version:
    log P0 error, do NOT load (refuse silent corruption)
```

Migrácia musí byť idempotentná (re-aplikácia rovnakej migrácie na už migrovaný state je no-op alebo error, nie tichá duplicita). Migrácia musí mať unit test (sample v0.x state file v `mod/tests/fixtures/`).

## 5. FU integrácia

### 5.1 Runtime hook pre `merchant.lua` (single point patch)

Patch súbor: `mod/patches/interface/windowconfig/merchant.lua.patch` alebo (ak FU vystavuje config, nie skript) cez wrapper script v `mod/scripts/sb2_merchant_hook.lua` registrovaný cez Starbound `merchant` UI config patch.

**Kontrakt hooku:**

- Vstup: `(item_id, base_price, merchant_context)` kde `merchant_context = { station_id, world_id, faction, merchant_type }`.
- Výstup: `(adjusted_price, top_reasons)` kde `top_reasons` je list 0–3 entry `{label, delta_pct}`.
- Side effects: hook môže zapísať `last_final_price` a `top_reasons_cache` do market state, ale nesmie meniť modifiers (tie sa menia iba cez `sb2_economy_day` tick alebo event handlery).

**Single point pravidlo:** všetky merchant UI calls (vanilla NPC, FU terramart) prejdú cez túto jednu funkciu. Žiadne paralelné patche pre konkrétneho merchanta v v0.1.

### 5.2 `sb2_market.object` entity spec

Vlastná placeable entity v `mod/objects/sb2_market/sb2_market.object` + sprite `mod/objects/sb2_market/sb2_market.png`.

- Funkčne: terminál ktorý po interakcii otvorí "breakdown panel" pre stanicu na ktorej je umiestnený. NIE merchant – iba info display.
- V v0.1 placeable cez admin spawn (`/spawnitem sb2_market`); proper crafting recipe v v0.5+.
- Renderuje plný zoznam tracked items pre daný station + ich modifier breakdown (nie iba top 3).

### 5.3 Tooltip extension v merchant UI

Mechanizmus:
- Po výpočte ceny hook zapíše `top_reasons` do dočasnej structure dostupnej z UI scriptu.
- UI script (patch na merchant tooltip render) prečíta `top_reasons` a pridá pod base tooltip 3 riadky vo formáte:
  ```
  +30% Blokáda Apexov
  +20% Špecializácia stanice (ťažba)
  -8% Hráčsky tlak (predaj 24h)
  ```
- Riadky používajú `sb2.economy.reason.<label>` lokalizačné kľúče (žiadne hardcoded stringy).

**Kedy sa `top_reasons_cache` zapisuje do market state:**
- Pri každom `sb2_economy_compute_price()` call, ktorý reálne prepočítal cenu – t.j. v každom z troch recompute momentov: lazy on-read (otvorenie merchanta s expirovaným cache), event-driven push (blokáda, transakcia, konvoj), heartbeat day-tick.
- NIE pri samotnom otvorení merchanta, ak je cache ešte čerstvý (`age < recompute_max_age_ticks`). V tom prípade UI iba prečíta existujúci `top_reasons_cache` z market state.
- Dôvod: `sb2_market.object` breakdown panel potrebuje cache aktuálny aj keď daného merchanta nikto neotvoril – preto sa zapisuje pri každom recompute, nie iba pri tooltip rendere.

Detailný UI layout spec ide nad rozsah tohto doc – ak presiahne 2 strany, vyhradíme samostatný sub-design `docs/economy-ui.md`.

### 5.4 Breakdown panel UI (pre `sb2_market` object)

- Tabuľka: item | base | M_local | A_regional | M_global | player_pressure | final | Δ vs včera.
- Filter: kategória, len-changed-today.
- Read-only, žiadny obchod cez tento panel v0.1.

### 5.5 FU version compatibility check

V `mod/scripts/sb2_economy_init.lua` (popis, nie kód) prítomná konštanta `SB2_FU_VERSION_COMPATIBILITY = { min = "6.4.0", tested_up_to = "6.5.x" }`.

Pri init:
1. Pokus o detekciu FU verzie cez známy FU config (napr. `/_FUversionconfig.config` ak existuje, alternatívne cez prítomnosť signature itemu).
2. Ak FU verzia mimo range → log warning, prepnúť do **graceful degradation módu**:
   - hook vráti FU originálnu `base_price`,
   - `top_reasons` = `[{label = "sb2_static_fallback", delta_pct = 0}]`,
   - žiadny crash, žiadne zapisovanie do market state,
   - UI tooltip zobrazí "DPS disabled: FU version mismatch".
3. Ak FU vôbec nie je nainštalovaná → hard error pri load (FU je tvrdá dependencia per vízii).

## 6. Edge cases

Každý edge case má detection → reaction → expected outcome.

### 6.1 Žiadny obchod na planéte X dní

- **Detection**: `current_day - last_recompute_day > inactivity_threshold` (default 5 dní) pri otvorení merchanta.
- **Reaction**: aplikuje sa decay formula (sekcia 3.5) `n`-krát, kde `n = days_elapsed`, v jednom batchu (nie n separátnych tickov). Player pressure sa nuluje (denný reset by sa stal aj tak).
- **Expected outcome**: ceny sa približujú k base hodnotám smerom k 0 % modifikátoru. Po ~30 dňoch inactivity je modifier prakticky `base ± jitter`.

### 6.2 Hráč vyťaží všetko (extreme supply na strane hráča, predáva)

- **Detection**: `transaction_volume / daily_turnover_baseline > 5.0` v jednej transakcii.
- **Reaction**: aplikuje sa formula z 3.4, ale `P_delta` clamped na `-player_pressure_cap` (-0.5). Navyše do `pending_events` sa zapíše `{type: "extreme_glut", item, magnitude: P_delta}`, ktorý pri ďalšom day ticku vygeneruje aditívny regional modifier (-10 %) na susedné stanice, aby sa glut "rozliel" v regióne.
- **Expected outcome**: cena okamžite klesne o 50 %, susedné stanice o 10 % na 2–3 dni. Žiadny exploit cez splitnutie do menších transakcií (denný `P_pressure` sa kumuluje).

### 6.3 Hráč predá obrovskú zásobu (extreme glut, symetricky)

- Identicky ako 6.2, len so symetrickým znamienkom – ale v 6.2 je už pokrytý sell side. Pre **buy side extreme** (hráč vykúpi celý stock):
- **Detection**: rovnako, `share > 5.0`, smer = buy.
- **Reaction**: `P_delta = +cap`, `pending_event = "extreme_scarcity"`, susedné stanice dostávajú +10 % na 2–3 dni.
- **Expected outcome**: cena vyletí o 50 %, hráč nemôže obratom kúpiť za starú cenu.

### 6.4 FU mod zmení tag taxonómiu

- **Detection**: pri init scan – pre vzorku 20 itemov z `item_overrides` v `sb2_economy_tags.config` overiť, či ich resolvovaný FU tag list stále obsahuje očakávanú kategóriu.
- **Reaction**: ak >20 % vzorky nesedí → log warning "FU tag taxonomy drift detected, X items mismatched", prejsť do degradation módu **iba pre mismatched items** (vrátia static price), ostatné fungujú normálne.
- **Expected outcome**: žiadny crash. Používateľ vidí v log súbore zoznam itemov ktoré treba updateovať v `item_overrides`. Manual fix cez update mod-u.

### 6.5 Co-op: 2 hráči transakcia naraz

- **Detection**: dve transakcie pre rovnaký `(station_id, item_id)` v rovnakom day ticku s timestampami < 2 s apart.
- **Reaction**: eventual consistency – obe transakcie sa aplikujú **sekvenčne podľa serverového poradia prijatia** (Starbound MP používa host-authoritative model). Druhý hráč vidí cenu z prvej transakcie aplikovanú po max 30 s sync delay.
- **Expected outcome**: host hráč je authority. Klient ktorý urobí transakciu druhý môže dostať `transaction_rejected` ak medzitým cena vyletela mimo jeho akceptovaného range (Starbound merchant UI to už natívne rieši pre stock count, využijeme rovnaký pattern pre price). Žiadny rollback prvej transakcie.
- **Globálne eventy (blokády, vojny, faction_global_modifiers):** generuje a aplikuje výhradne **host**. Klienti dostávajú zmeny push-om cez universe state sync, nikdy nevyhlasujú vlastné globálne eventy – tým sa vyhneme konfliktu pri 2+ klientoch a `sb2_economy_global.json` má vždy jediného writera.

### 6.6 Save z v0.1 načítaný v v0.2

- **Detection**: `schema_version = 1`, current `SB2_SCHEMA_VERSION = 2`.
- **Reaction**:
  1. Backup `sb2_economy_global.json` → `sb2_economy_global.json.bak.v1`.
  2. Pre každú stanicu v `world.properties` backup market state pod `sb2_market_state_<id>_bak_v1` property.
  3. Aplikovať `migrate_v1_to_v2(state)` na každý state objekt.
  4. Append entry do `migration_history`.
  5. Save migrated state.
  6. Log `[SB2] Migration v1 → v2 completed for N markets, M global keys`.
- **Expected outcome**: hra pokračuje. Hráč môže v `KNOWN_ISSUES.md` nájsť zoznam zmien v v0.2 schéme. Ak migrácia zlyhá → P0 error message, hra sa nenačíta, backup ostáva nedotknutý.

## 7. Performance

### 7.1 Per-tick budget (cieľ <1 ms na entity)

`sb2_economy_day` tick je rare (raz za 30 min realtime), takže nemá tvrdý 1 ms strop – môže trvať aj 50 ms ak prepočítava N markets. Hot path je hook pri otvorení merchanta:

- Lookup market state: O(1) hash lookup.
- Recompute single item: O(K) kde K = počet modifierov (typicky 5–8).
- Cieľový rozpočet pre `sb2_economy_compute_price()`: <0.2 ms na call.
- Cieľový rozpočet pre `sb2_economy_day_tick()` per market: <2 ms (akceptovateľné lebo non-frame-critical).

### 7.2 Memory footprint per market

Odhad pre stanicu so 30 tracked items:
- per item: ~400 B JSON (modifiers + reasons cache) → ~12 KB.
- pending_events: typicky <5 entries × ~100 B → 0.5 KB.
- metadata: ~0.5 KB.
- **Spolu ~13 KB per market**, serializované.

Pre 100 navštívených staníc v session: ~1.3 MB v globálnom storage. Akceptovateľné.

### 7.3 Lazy load benchmark targets

- Načítanie market state pri prvej návšteve sveta v session: <50 ms (vrátane parsovania JSON).
- Push update do `sb2_economy_global.json` pre "veľký" event: <100 ms (atomic write cez temp file + rename).
- Pre 100 staníc v `known_stations`: full scan + integrity check <200 ms.

Ak benchmark zlyhá v playteste → P1 issue, optimalizácia v ďalšom release.

## 8. Schema versioning

### 8.1 Kontrakt migrácie

Každá migrácia: `migrate_v<N>_to_v<N+1>(state_table) → new_state_table`. Pravidlá:

- Pure function (žiadne side effects okrem logu).
- Idempotentná detekcia: ak vstup už má `schema_version = N+1`, vrátiť bez zmeny + warning.
- Nesmie crashnúť na chýbajúce voliteľné polia (defensive defaults).
- Musí pridať entry do `migration_history`.
- Musí mať fixture test (sample state v `mod/tests/fixtures/v<N>/...`) ktorý overí výsledok.

### 8.2 Backup mechanism

Pred každou migráciou:
- Per-world state: skopírovať hodnotu `world.setProperty` do `<key>_bak_v<old_version>` property na rovnakom worlde (žiadny file I/O).
- Universe state: kopírovať `storage/sb2_economy_global.json` → `storage/sb2_economy_global.json.bak.v<old_version>`.

Backup operácia musí prebehnúť **pred** akoukoľvek mutáciou. Ak backup zlyhá (disk full, permission) → migrácia sa neuskutoční, P0 error, load fail s jasnou message.

### 8.3 Lokácia backupov a retention

- Per-world backupy: ostávajú v world properties navždy (sú malé). Retention: nikdy nemažeme automaticky; v0.5+ pridáme `/sb2_cleanup_backups` admin príkaz.
- File backupy: `storage/sb2_economy_global.json.bak.v<N>` – retention: posledných **3** verzie. Staršie zmazať pri úspešnej migrácii (až po overení integrity nového stavu).

### 8.4 Migration test framework od dňa 1

- `mod/tests/migration_test.lua` (popis): načíta každú fixture v `mod/tests/fixtures/v<N>/`, aplikuje migration chain do current_version, porovná s `mod/tests/fixtures/v<current>/expected/<name>.json`.
- Framework spúšťame **manuálne v dev móde** (Starbound nemá CI), používateľ spustí cez admin príkaz `/sb2_run_migration_tests`. Výsledok loguje pass/fail per fixture.
- Pri release každej minor verzie pridať aspoň jednu novú fixture pre danú schema bump.

## 9. Test plan

### 9.1 Manuálne testy (krok-po-kroku, používateľ vykonáva)

1. **Smoke test (existencia):**
   1. Nainštalovať mod, načítať vanilla save bez existujúceho economy state.
   2. Skontrolovať log: očakávaný riadok `[SB2] Economy init OK, FU version <X> in range, schema v1 fresh.`
   3. Otvoriť ľubovoľného vanilla NPC merchanta.
   4. Očakávané: ceny sa zobrazia, tooltip má sekciu top reasons (môže byť prázdna pre nový market).

2. **Day tick test:**
   1. V `sb2_economy.config` znížiť `tick_realtime_seconds` na 60 (1 min realtime).
   2. Otvoriť merchanta, zapamätať si cenu liquidwater.
   3. Počkať 5 minút realtime (5 day tickov).
   4. Otvoriť merchanta znova.
   5. Očakávané: cena sa mohla pohnúť cez jitter (max ±5 %), top_reasons obsahuje jitter entry.

3. **Player pressure test:**
   1. Predať 500× liquidwater jednému merchantovi.
   2. Skontrolovať tooltip – top_reasons má `Player pressure (sell): -50%`.
   3. Cena clamped na `base * 0.5 - epsilon`.
   4. Počkať 1 day tick, P_pressure sa resetuje na 0.

4. **Decay test:**
   1. Vyvolať `+30 %` regional event (cez debug príkaz, viď 9.2).
   2. Skončiť event, počkať 10 day tickov.
   3. Modifier by mal byť pod `1.0 + 0.30 * 0.85^10 ≈ 1.06`.

5. **Co-op consistency test:**
   1. Host + 1 klient v rovnakej session.
   2. Obaja navštívia tú istú stanicu, otvoria toho istého merchanta.
   3. Porovnať zobrazené ceny pre vybraných 5 itemov.
   4. Očakávané: zhodné na cent (po 30 s sync delay).

6. **Graceful degradation test:**
   1. V `SB2_FU_VERSION_COMPATIBILITY` umelo nastaviť `min = "999.0.0"`.
   2. Reload save.
   3. Očakávané: log warning, merchant ceny sú static FU originály, tooltip ukazuje "DPS disabled: FU version mismatch", žiadny crash.

7. **Migration test:**
   1. Pripraviť fixture state s `schema_version = 0` (umelo).
   2. Načítať save.
   3. Skontrolovať: `*.bak.v0` súbor existuje, state v novej schéme, `migration_history` obsahuje entry.

8. **Success criteria check:**
   1. Bežná hra 5 in-game dní.
   2. Sledovať liquidwater a corefragment na min 3 staniciach.
   3. Aspoň jedna komodita sa pohla o ≥30 % – success.

### 9.2 Debug overlay spec

Admin/dev príkaz `/sb2_debug_market <station_id>`:

Vystúp do chat/log:
```
=== SB2 Market: <station_id> @ day <N> ===
liquidwater (base 5):
  M_local       = 0.85    [supply_demand: 0.85, station_spec: 1.00]
  A_regional    = -0.05   [trade_flow: -0.05]
  M_global      =  1.00
  P_pressure    = -0.08
  final_raw     =  4.05   final_clamped = 4
corefragment (base 30):
  M_local       =  1.70   ...
  ...
=== Pending events: [trade_flow_arrival titaniumbar +12% on day 146] ===
=== Last recompute: day 145, age 0 ticks ===
```

Druhý príkaz `/sb2_debug_economy_global` zobrazí universe-level modifiers a aktívne trade flows.

### 9.3 FU compatibility smoke test checklist

Po každom FU update spustiť (manuálne, viď nasledujúci doc):

1. Otvoriť 3 rôzne typy merchantov: vanilla NPC, FU terramart, vanilla planet vendor.
2. Pre každého: skontrolovať že tooltip ukazuje DPS reasons (nie static fallback).
3. Spustiť `/sb2_debug_market` pre jednu stanicu z každej kategórie.
4. Skontrolovať log: žiadne `[SB2] WARN: FU tag taxonomy drift`.
5. Predať jeden item, overiť že P_pressure sa zapísal.
6. Pri zlyhaní hociktorého kroku → P1 issue + entry v `KNOWN_ISSUES.md`.

Detailný checklist sa udržiava v `docs/COMPATIBILITY_TESTING.md` (vytvorí sa pri prvej FU update príležitosti).

## 10. Otvorené otázky

1. **`world.setProperty` size limit** – nie je overené či má Starbound 5.1 API hard limit pre veľkosť stringu uloženého cez `world.setProperty`. Ak áno (napr. 64 KB), per-station market state s 30+ items by mohol naraziť. Riešenie: rozdeliť do viacerých kľúčov per kategória, alebo presunúť do file-based storage. Vyžaduje overenie v prototype.
2. **Atomic write `storage/sb2_economy_global.json`** – Starbound Lua API pre file I/O je obmedzené. Potrebujeme overiť, či `root.assetJson` / asset API vie písať, alebo musíme ísť cez `world.setProperty` na placeholderovom worlde. Alternatíva: drop universe-level state, držať všetko per-world (komplikuje multi-world propagáciu).
3. **Detekcia FU verzie** – FU nepublikuje stabilný version endpoint. Treba zistiť, či existuje config s verziou alebo musíme detekovať cez signature itemy (krehké). Pending: investigation v prvej implementačnej iterácii.
4. **Jitter randomness API** – Lua 5.1 `math.random` nie je seedovateľné v multi-instance bezpečným spôsobom. Potrebujeme vlastný PRNG (napr. xorshift32) implementovaný v `sb2_prng.lua`. Otvorené: bude stačiť 32-bit perioda, alebo treba 64-bit.
5. **Balansovanie default konštánt** – `impact_coefficient = 0.15`, `decay_factor = 0.85`, `daily_turnover_baseline` per kategória – tieto sú educated guesses. Definitívne hodnoty pendujú na 2–3 playtest sessions po implementácii v0.1 prototypu.
6. **Persistence pri "abandoned save"** – ak hráč navštívi 200 staníc a pol roka nehrá, máme 200 market states v memory pri load. Lazy unload strategy nie je v scope v0.1, ale môže byť potrebná v v0.5.
7. **Konflikt s inými mods ktoré patchujú `merchant.lua`** – ak iný mod taktiež patchuje rovnaký súbor (RFC 6902 patch order nie je deterministicky definovaný v Starbound asset loader), poradie patchov môže byť neurčité. Pending: dokumentovať známe konflikty v `KNOWN_ISSUES.md`.

## Status

- **Verzia**: v1 draft
- **Dátum**: 2026-05-24
- **Fáza systému**: Design (pred-implementácia)
- **Cieľová release**: v0.1
- **Súvisiace docs**: `docs/vision.md`, `CLAUDE.md`, (pripravované) `docs/COMPATIBILITY_TESTING.md`, (pripravované sub-design) `docs/trade-flow-v01.md`, `docs/economy-ui.md`
