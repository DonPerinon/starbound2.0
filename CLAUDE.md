# Starbound 2.0 – FU Extension Mod

## Čo je tento projekt
Fanúšikovská nadstavba pre Starbound + Frackin' Universe, ktorá premieňa galaxiu z kulisy na živý systém:
- **Living Economy** – dynamické ceny podľa supply/demand, NPC konvoje, špecializácia planét
- **Faction Influence** – sféry vplyvu, dynamické vojny/aliancie z mechaník
- **Tactical Space Combat** – modulárne lode, real-time 2D combat, boarding akcie
- **Emergent Storytelling** – príbeh vzniká z interakcie systémov, nie zo skriptov
- **FU-Native Integration** – vrstva NAD FU, nie paralelný svet

## Cieľová skupina (poradie dôležitosti)

1. **FU Veterán (primárny)** – 200+ hodín v FU, hľadá hĺbku a komplexitu, chce learning curve XY hodín, ocení mechaniku ktorú trvá pochopiť
2. **Strategy fanúšik (sekundárny)** – Stellaris/X4 hráč, chce politickú mapu a konsekvencie
3. **Trader/builder (terciárny)** – arbitrage, podnikanie, vizuálny progress
4. **Co-op skupinka (paralelný)** – 2-8 kamarátov zdieľa galaxiu

## Kľúčové design principles

### Transparent depth
Mechaniky sú hlboké (8+ vrstiev), ale efekty sú **vždy čitateľné**. Hráč nemá hádať ČO sa deje, len AKO to využiť. Cena ukazuje dôvod ("+30% blokáda Apexov"). Frakčná AI je transparentná. Inšpirácia: Factorio, Stellaris (nie Dwarf Fortress).

### Learning curve is a feature
XY hodín na pochopenie systému je **správny dizajn**, nie bug. FU veterán to ocení. Žiadne hand-holding tutoriály.

### FU compatibility first
Mod nikdy nepretvára FU mechaniky, iba ich rozširuje. Ak FU funkciu má, použijeme ju. Patche cez JSON (RFC 6902), runtime hooks namiesto statických prepisov.

### SP-first, co-op compatible
Primárny dizajn pre singleplayer. Co-op (2-8 hráčov, trust-based) funguje s eventual consistency. **Out of scope: persistent 24/7 servery, PvP-zamerané mechaniky.**

### Performance over features
Cieľ <1ms per entity tick je tvrdý strop. Feature ktorá ho prekročí sa redesignuje alebo zahodí. Lazy evaluation – výpočty pri zmenách, nie každý frame.

### Data-driven content
Nový content (komodity, frakcie, lode) cez JSON, nie Lua. Schema versioning od dňa 1. Modderi môžu rozširovať bez forku.

### No silent failures
Mod radšej crashne s jasnou error message než tichý data corruption. Backup pred risky migrations.

### Design before code
Každý netriviálny systém má design doc v `docs/` skôr ako vznikne Lua kód.

## Technický stack
- **Lua 5.1** (Starbound engine používa Lua 5.1, NIE novší!)
- **JSON** pre konfigy a content
- **Sprites**: PNG, paleta a štýl Starbound (16x16 alebo násobky)
- **Dependencia**: Frackin' Universe (tvrdá, nie optional)
- **Engine**: výlučne Starbound Lua API a JSON config systém (žiadny vlastný engine, fyzika, shaders)

## Frakčná AI (incremental)
- **v0.1**: pure rules-based (quick & dirty)
- **v0.5**: + utility AI vrstva
- **v1.0**: + personality modifiers (Aggressor, Trader, Isolationist, Opportunist, Defender)
- **v2.0+**: goals/agendas, inter-faction memory
- **Out of scope**: LLM-driven dialogue, ML, neural networks

## Modding philosophy (incremental platform)
- **v0.1**: data-driven JSON, repo open-source
- **v0.5**: docs/MODDING.md, stable schemas, example extension mod
- **v1.0**: public Lua hooks pre tretie strany
- **Pravidlá od dňa 1**: data v JSON / logika v Lua, schema versioning, repo verejný (GitHub)

## Stability standards
- **No silent data corruption** – ak môže byť save poškodený, radšej crash
- **Schema versioning** v každom perzistent JSON-e (`version: 1` pole)
- **Backup before risky migrations** pri major verziách
- **KNOWN_ISSUES.md** v repo, transparentné
- **Bug klasifikácia P0-P3**:
  - P0 = save corruption / crash / mod uchne hru → fix do 7 dní
  - P1 = feature nefunguje, edge case crash → next update
  - P2 = misbehavior, UI bugy, balance → keď bude čas
  - P3 = cosmetic, typos → keď sa narazí

## Konvencie kódu

### Naming
- Lua súbory: `snake_case.lua`
- JSON itemy: `itemname.item`, `itemname.object`
- Patche: `original_path.config.patch`
- Lua funkcie: `camelCase`
- Lua premenné: `snake_case`
- Mod prefix: `sb2_` pre všetky vlastné identifikátory (napr. `sb2_economy_tick`)

### Priečinky
- `mod/scripts/` – nová Lua logika
- `mod/items/` – nové itemy
- `mod/objects/` – nové objekty (markety, terminály)
- `mod/patches/` – patche existujúcich FU/vanilla súborov
- `docs/` – design dokumenty

### Patternové pravidlá
- Žiadne hardcoded stringy (lokalizácia friendly)
- Žiadne hardcoded factions/items (data-driven)
- `try/catch` pri load logike (no silent failures)
- Komentuj public funkcie ako "stable API" alebo "internal"

## Out of scope (globálne)
- 3D vesmírny combat (ostávame 2D)
- Prepisovanie FU balance (ceny, recepty, damage existujúcich itemov)
- RTS-style flotily (mikromanažment 20+ lodí)
- LLM-driven NPC dialogue, ML, neural networks
- Persistent MMO-style servery, stovky hráčov
- PvP-zamerané mechaniky
- Steam Workshop integrácia (v1.0+, nie teraz)
- Vlastný engine, fyzika, shaders
- Telemetria, mikrotransakcie, externé sieťové volania
- Vanilla Starbound bez FU (FU je tvrdá závislosť)

## Aktuálny stav projektu
- **Fáza**: Implementácia jadra DPS (čisté moduly hotové), engine hooky čakajú na prototypy
- **Aktívny systém**: Dynamic Pricing System (v0.1)
- **Hotové moduly**: `sb2_util`, `sb2_config`, `sb2_prng`, `sb2_economy_tags`, `sb2_pricing`, `sb2_market_state`, `sb2_migrations`, `sb2_storage` (testy: `python3 tools/run_lua_tests.py`)
- **Najbližší míľnik**: výsledky prototypov Q1/Q2 a Q3 (`prototypes/`) zapísané do `docs/economy-system.md`, potom universe backend, merchant hook, day tick host a `sb2_market` terminál
- **Známa odchýlka od docu**: `trade_flow_arrival` cenu znižuje (viac ponuky), `departure` zvyšuje; doc 2.3/4.1 má znamienka nejednoznačné, vyriešiť pri revízii v2
- **Analýza stavu**: `docs/planned-features-analysis.md` (2026-09-25)

## Kľúčové dokumenty
- `docs/vision.md` – celková vízia projektu (zdroj pravdy)
- `docs/economy-system.md` – design ekonomického systému (v1 draft)
- `docs/influence-system.md` – design frakčného vplyvu (chýba)
- `docs/MODDING.md` – API pre tretie strany (v0.5+)
- `KNOWN_ISSUES.md` – aktívne bugy (vytvoríme pri prvom bugu)

## Testovanie
- Claude (a Claude Code agenti) nemôžu spúšťať Starbound
- Po každej zmene používateľ testuje manuálne
- Pri navrhovaní agenti pridávajú "Test plan" sekciu – čo treba otestovať

## Pre agentov
Pred prvou akciou si prečítajte tento CLAUDE.md celý. Pri konflikte medzi pôvodným promptom a týmto dokumentom **má prioritu CLAUDE.md**. Pri konflikte medzi CLAUDE.md a `docs/vision.md` **má prioritu vision.md** (je to zdroj pravdy pre design).