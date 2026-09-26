# Faction Influence System – Design Document (v0.1 rozsah)

## Out of scope of this document

Tento dokument pokrýva **v0.1**: sféry vplyvu ako dáta, rules-based frakčnú AI a jej väzbu na Dynamic Pricing System (DPS). Nasledujúce oblasti sú vyčlenené:

- **Utility AI vrstva (v0.5)** – skórovanie akcií, samostatný doc `docs/influence-utility-v05.md` vznikne, keď v0.1 rules bežia v hre.
- **Personality modifiers (v1.0), agendy a pamäť (v2.0+)** – iba rezervované polia v schéme.
- **Mapa vplyvu ako UI** (vlastný canvas ScriptPane) – tento doc definuje dátový kontrakt `sb2_faction_status`, nie pixel layout.
- **Vojenská prítomnosť ako entity** (hliadky, lode) – v0.1 je prítomnosť iba číslo.

## 1. Cieľ systému

Faction Influence System (ďalej FIS) je druhý systém Starbound 2.0 a tvorí jadro pillaru **Faction Influence**. Dáva frakciám merateľný vplyv na staniciach a jednoduché, deterministické správanie, ktoré z ekonomického stavu vyrába viditeľné udalosti (blokády, vojny, mier).

**Tvrdé požiadavky (zo success criteria vízie):**

- V testovacej galaxii nastane minimálne 1 dynamicky spustená vojna alebo zmena hraníc sféry vplyvu za 10 herných dní, bez zásahu hráča.
- Frakčná AI je čitateľná: hráč vidí stav frakcie, motiváciu (ktoré pravidlo vystrelilo) a plánovanú akciu.
- Per-tick logika neprekročí 1 ms na entity. FIS nemá žiadnu per-frame logiku, beží iba v day ticku.
- Schema versioning a backup pred migráciou, rovnaký runner ako DPS (`sb2_migrations`).
- Frakcie sú dáta (JSON), nie Lua. Nová frakcia = nový záznam v configu.
- Co-op deterministic: rovnaký vstup → rovnaké rozhodnutie. Ties sa riešia zoradením podľa id, nie náhodou.

**Nie je cieľom v0.1:**

- „inteligentná“ AI; cieľ je, aby svet žil, aj keď je AI dummy,
- zápis do `sb2_market_state` (DPS číta frakčný stav sám, viď 2.4),
- diplomatické akcie hráča (envoy, standing) – koncepty pre v0.5+,
- vizuálne prejavy vo svete (NPC, lode, dekorácie).

## 2. Hlavné mechaniky

### 2.1 Sféra vplyvu ako per-station tabuľka

Vplyv nie je polygon na mape. Je to tabuľka `influence[station_id][faction_id] = 0.0 … 1.0`, kde súčet za stanicu je ≤ 1.0 (zvyšok je „nikto“). Sféra frakcie = množina staníc, kde má najvyšší vplyv a zároveň ≥ `sphere_threshold` (default 0.4).

Stanice sú tie isté záznamy ako `known_stations` v DPS universe stave. FIS nevie o stanici, ktorú hráč nikdy nenavštívil (rovnaké lazy pravidlo ako ekonomika).

### 2.2 Zdroje zmeny vplyvu (per day tick)

Každý day tick sa pre každú známu stanicu prepočíta vplyv každej frakcie:

```
delta = trade_presence * w_trade
      + military_presence * w_military
      - population_penalty * w_population
influence_new = clamp(influence_old + delta, 0, 1)
```

potom normalizácia: ak súčet > 1, všetky hodnoty sa proporčne škálujú.

| Zložka | Zdroj dát (read-only) | v0.1 hodnota |
|---|---|---|
| `trade_presence` | podiel konvojov frakcie, ktoré na stanicu dorazili za posledných 5 dní (`trade_flows` v DPS universe stave, pole `faction` na konvoji) | 0.0 … 1.0 |
| `military_presence` | 1.0 ak frakcia práve blokuje systém stanice, 0.5 ak blokuje susedný systém, inak 0 | z `faction_state.events` |
| `population_penalty` | 1.0 ak stanica má aktívny `regional_event` typu blokáda od inej frakcie dlhšie ako 3 dni (obyvatelia strácajú dôveru v ochrancu) | z DPS regional modifiers |

Váhy `w_*` sú v `sb2_factions.config` (default `w_trade = 0.04`, `w_military = 0.06`, `w_population = 0.03` per deň). Pri týchto hodnotách prevzatie stanice z 0.6 na 0.4 trvá rádovo 5–8 dní blokády, čo dáva „zmenu hraníc za 10 dní“ zo success criteria.

### 2.3 Rules-based AI (v0.1 rozhodovací strom)

Každý day tick, pre každú frakciu v poradí podľa `faction_id` (deterministicky), sa vyhodnotí presne tento strom. Prvé pravidlo, ktoré platí, vyberie akciu; ostatné sa nevyhodnocujú. Každé pravidlo má `id`, ktoré sa zapíše ako motivácia.

```
R1  if at_war_with ~= nil and war_days >= max_war_days           -> action: PEACE (vojna vyhasne)
R2  if at_war_with ~= nil                                        -> action: CONTINUE_WAR (drží blokádu hubu nepriateľa)
R3  if hunger > hunger_threshold and aggression < aggression_cap -> action: RAISE_AGGRESSION (+1)
R4  if aggression >= blockade_threshold and target exists        -> action: BLOCKADE(target)
R5  if aggression > 0 and hunger <= hunger_threshold             -> action: CALM_DOWN (-1)
R6  else                                                         -> action: HOLD
```

Definície:

- `hunger` = `1 - faction_food_availability`, kde `faction_food_availability` je priemer `local_modifiers.supply_demand` pre itemy kategórie `food` cez stanice v sfére frakcie, prevrátený do 0…1 (supply_demand 0.5 = veľký nedostatok → hunger 0.75; 1.0 → 0.5; 1.5 → 0.25). Presný prevod: `availability = clamp(supply_demand / 2, 0, 1)`. Frakcia bez staníc má `hunger = 0`.
- `target` pre R4 = stanica s najvyšším `daily_turnover` (súčet) medzi stanicami, kde má **iná** frakcia sféru a ktorá je v tom istom alebo susednom systéme ako niektorá stanica agresora. Ak žiadna, R4 neplatí.
- `BLOCKADE(target)` vytvorí `faction_event` typu `blockade` s `expires_day = day + blockade_days` (default 14) a `regional_key = system(target)`. Ak obeť (frakcia so sférou nad `target`) má `influence ≥ sphere_threshold`, vzniká **vojna**: obe strany dostanú `at_war_with`.
- `PEACE` zruší blokády oboch strán, `at_war_with = nil`, `aggression = 0`, `war_days = 0`.

Prahy v configu: `hunger_threshold = 0.6`, `blockade_threshold = 3`, `aggression_cap = 5`, `max_war_days = 20`, `blockade_days = 14`.

### 2.4 Väzba na DPS: pull, nie push

FIS nikdy nevolá `sb2_market_state`. Väzba je obojsmerná, ale iba cez dáta a iba v day ticku:

- **FIS číta DPS**: agregáty `faction_food_availability`, `daily_turnover` per stanica, `trade_flows`. Read-only.
- **DPS číta FIS**: pri recompute dostane `context.regional` a `context.global` z `sb2_faction_events.toModifiers(faction_state, station)` – blokáda systému = `regional_event` label `blockade_<faction>` s magnitúdou `blockade_price_modifier` (default +0.30), vojna = `global_event` label `war_<a>_<b>` s magnitúdou `war_global_modifier` (default 1.05). Aktívne eventy majú `expires_day`, DPS ich drží ako `active_sources` (decay 1.0), po expirácii klesajú štandardne.

Toto spĺňa „AI nepíše do market state“ z economy docu 2.4 a zároveň dáva v0.1 viditeľný efekt: cena ukáže „+30 % blokáda Apexov“.

### 2.5 Transparentnosť: `sb2_faction_status` kontrakt

Pre každú frakciu je po day ticku k dispozícii:

```
{
  faction_id = "apex",
  state = { aggression = 3, hunger = 0.71, at_war_with = "floran", war_days = 2 },
  motivation = { rule = "R2", inputs = { hunger = 0.71, threshold = 0.6 } },
  planned_action = { type = "CONTINUE_WAR", target = "fenrir_hub", expires_day = 158 },
  next_rule_preview = { rule = "R1", when = "war_days >= 20 (day 176)" },
  sphere = { "apex_refinery_02", "outpost_terramart_01" }
}
```

UI (mapa vplyvu, faction panel) číta iba toto. Lokalizačné kľúče: `sb2.faction.rule.<id>`, `sb2.faction.action.<type>`.

## 3. Konkrétne formuly

### 3.1 Normalizácia vplyvu

```
total = sum(influence[station][f] for f)
if total > 1.0: influence[station][f] = influence[station][f] / total  (pre všetky f)
```

### 3.2 Hunger

```
availability(f) = mean over stations s in sphere(f), items i with category food:
                  clamp(market_state[s].items[i].local_modifiers.supply_demand / 2, 0, 1)
hunger(f) = 1 - availability(f)      -- frakcia bez staníc alebo bez food itemov: hunger = 0
```

### 3.3 Výber cieľa blokády (deterministický)

```
candidates = stations where sphere_owner(s) ~= f and sphere_owner(s) ~= nil
             and system(s) in neighbourhood(f)
sort candidates by (turnover desc, station_id asc)
target = candidates[1]
```

`neighbourhood(f)` = systémy staníc v sfére f + systémy, ktoré sú podľa `known_stations.world_coords` do `neighbour_distance` (default 2 sektory v X/Y). Bez susedov → R4 neplatí.

### 3.4 Determinizmus

Žiadna náhoda v pravidlách. Jediné použitie PRNG: `sb2_prng.hash(world_seed, "faction", day)` pre poradie vyhodnotenia, ak by v budúcnosti bolo potrebné rotovať prvého ťahajúceho. V0.1 je poradie pevné podľa `faction_id`.

## 4. Dátové štruktúry (JSON schémy)

### 4.1 Config frakcií `mod/configs/sb2_factions.config`

```json
{
  "schema_version": 1,
  "weights": { "w_trade": 0.04, "w_military": 0.06, "w_population": 0.03 },
  "thresholds": {
    "sphere_threshold": 0.4, "hunger_threshold": 0.6, "blockade_threshold": 3,
    "aggression_cap": 5, "max_war_days": 20, "blockade_days": 14, "neighbour_distance": 2
  },
  "effects": { "blockade_price_modifier": 0.30, "war_global_modifier": 1.05 },
  "factions": {
    "apex":   { "name_key": "sb2.faction.apex",   "color": [198, 120, 221], "home_races": ["apex"] },
    "floran": { "name_key": "sb2.faction.floran", "color": [123, 216, 106], "home_races": ["floran"] },
    "human":  { "name_key": "sb2.faction.human",  "color": [86, 168, 255],  "home_races": ["human"] },
    "hylotl": { "name_key": "sb2.faction.hylotl", "color": [90, 200, 220],  "home_races": ["hylotl"] },
    "avian":  { "name_key": "sb2.faction.avian",  "color": [240, 200, 90],  "home_races": ["avian"] },
    "glitch": { "name_key": "sb2.faction.glitch", "color": [180, 180, 200], "home_races": ["glitch"] },
    "novakid":{ "name_key": "sb2.faction.novakid","color": [255, 170, 80],  "home_races": ["novakid"] }
  },
  "initial_influence_by_race": 0.6
}
```

`home_races` mapuje rasu NPC obchodníka / typ stanice na frakciu pri prvom objavení stanice. FU frakcie (napr. Precursor, Elder) sa pridajú ako ďalšie záznamy bez zmeny Lua.

### 4.2 Universe stav `sb2_faction_state` (schema 1)

Uložený tým istým universe backendom ako `sb2_economy_global` (rozhodne prototyp Q1/Q2; kandidát `player.setProperty` na hostovi).

```json
{
  "schema_version": 1,
  "day": 145,
  "factions": {
    "apex": { "aggression": 3, "hunger": 0.71, "at_war_with": "floran", "war_days": 2,
              "last_rule": "R2", "planned_action": { "type": "CONTINUE_WAR", "target": "fenrir_hub", "expires_day": 158 },
              "personality": null, "agenda": null }
  },
  "influence": {
    "outpost_terramart_01": { "apex": 0.61, "human": 0.22 },
    "fenrir_hub": { "floran": 0.55, "apex": 0.18 }
  },
  "events": [
    { "id": "ev_0001", "type": "blockade", "faction": "apex", "target_station": "fenrir_hub",
      "regional_key": "system_fenrir", "started_day": 145, "expires_day": 159, "cause": "R4" }
  ],
  "migration_history": []
}
```

Polia `personality` a `agenda` sú rezervované (v1.0, v2.0), v v0.1 vždy `null`.

### 4.3 Rozšírenie DPS záznamov

- `trade_flows[*].faction` (string) – frakcia konvoja; scheduler ho nastaví podľa sféry zdrojovej stanice.
- `known_stations[*].system_key` (string) – kľúč systému pre regionálne eventy; odvodený z `world_coords` (`"system_<x>_<y>_<z>"`).

Obe sú aditívne polia v schéme v1 (chýbajúce = defaulty), nevyžadujú migráciu.

## 5. FU integrácia

- Frakcie v0.1 = vanilla rasy; FU nemá vlastný frakčný systém, ktorý by sa dal duplikovať. FU rasy/NPC typy sa mapujú cez `home_races`.
- Rasa stanice pri prvom objavení: z NPC merchanta (`npc.species` v hooku) alebo z parametra `sb2_faction` na `sb2_market` objekte (dev override). Ak nič, stanica je neutrálna (vplyv 0 pre všetkých) a získava vplyv iba obchodom.
- Žiadne patche FU súborov. FIS je čistá Lua + JSON vrstva nad DPS dátami.

## 6. Edge cases

- **Žiadne známe stanice**: day tick FIS je no-op, všetky frakcie `HOLD`, hunger 0. Log raz za deň na úrovni info.
- **Frakcia bez sféry**: hunger 0, nikdy nedosiahne R3/R4, môže byť iba obeťou. Získať sféru môže obchodom (konvoje).
- **Všetky frakcie vo vojne**: R2 drží blokády, R1 ich po `max_war_days` ukončí; systém sa nezasekne, lebo `war_days` rastie nezávisle.
- **Dve frakcie chcú blokovať tú istú stanicu**: poradie podľa `faction_id`; druhá už nenájde cieľ so sférou obete (event existuje) a padne na R5/R6.
- **Save bez faction state (upgrade z DPS-only buildu)**: fresh init, influence z `home_races` pre známe stanice, log `[SB2] Faction state fresh, N stations seeded`.
- **Stanica zmizne z known_stations**: influence záznam ostáva (malý), eventy s cieľom na neznámu stanicu expirujú normálne.
- **Co-op**: FIS beží iba na hostovi (rovnako ako universe day tick DPS). Klient číta `sb2_faction_status` cez sync world property na spoločnom svete.

## 7. Performance

- Day tick: O(S × F) pre vplyv + O(F × S) pre výber cieľa, S = známe stanice (≤ 200), F = frakcie (≤ 10). Odhad < 5 ms na host pri 200 staniciach, non-frame-critical.
- Žiadny per-frame kód. Status kontrakt sa počíta raz per tick a cachuje.

## 8. Schema versioning

Rovnaké pravidlá ako economy doc 8.1–8.4: `sb2_migrations.register("faction_state", …)`, backup cez backend pred mutáciou, fixtures v `mod/tests/fixtures/faction_state/v<N>/`.

## 9. Test plan

### 9.1 Standalone (Lua testy mimo hry)

1. Normalizácia: tri frakcie s 0.5/0.5/0.5 → 0.333 každá.
2. Hunger: sphere s food supply_demand 0.5 → hunger 0.75; bez staníc → 0.
3. Strom: hunger 0.7, aggression 0 → R3; aggression 3 + cieľ → R4 vytvorí event a vojnu; war_days 20 → R1 mier.
4. Determinizmus: dva identické stavy → identické eventy a poradie.
5. `toModifiers`: aktívna blokáda → `regional_event` +0.30 pre stanice v systéme, iné stanice bez zmeny.
6. Success criterion simulácia: 3 frakcie, 6 staníc, 10 tickov s jednou stanicou s food supply_demand 0.4 → aspoň 1 vojna.

### 9.2 In-game (používateľ)

1. Po načítaní save: log `[SB2] Faction state fresh`.
2. `sb2_market` terminál na stanici v sfére: záložka „Frakcia“ ukazuje owner, vplyv, aktuálne pravidlo.
3. Debug terminál: tlačidlo „Force hunger apex 0.9“, počkať 4 day ticky → blokáda + cena potravín „+30 % blokáda Apex“.
4. Po 20 dňoch vojna skončí, modifikátor klesá decayom.

## 10. Otvorené otázky

1. **Detekcia rasy stanice** – `npc.species` je dostupné v NPC kontexte; či sa dá spoľahlivo získať v merchant hooku, rozhodne prototyp Q3 (kde je hook). Fallback: parameter na `sb2_market` objekte.
2. **Susednosť systémov** – `world_coords` z `known_stations` sú celestial súradnice; `neighbour_distance = 2` je odhad, kalibrovať playtestom.
3. **Universe backend** – rovnaká závislosť na Q1/Q2 ako `sb2_economy_global`.
4. **FU frakcie** – ktoré FU NPC typy majú byť samostatné frakcie (v0.5), a či majú home_races alebo home_stations.
5. **Balans prahov** – `hunger_threshold`, `blockade_threshold`, váhy vplyvu sú educated guesses; cieľ je 1 vojna / 10 dní bez hráča, overí 9.1 bod 6 a playtest.

## Status

- **Verzia**: v1 draft
- **Dátum**: 2026-09-26
- **Fáza systému**: Design (v0.1 rozsah), implementácia po DPS hookoch
- **Cieľová release**: v0.1
- **Súvisiace docs**: `docs/vision.md`, `docs/economy-system.md` (2.4, 4.2), `docs/planned-features-analysis.md` (sekcia 4)
