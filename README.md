# Starbound 2.0

Fanúšikovská nadstavba pre Starbound + Frackin' Universe, ktorá premieňa galaxiu z kulisy na živý systém.

## Vízia

- **Living Economy** – dynamické ceny podľa supply/demand
- **Faction Influence** – sféry vplyvu, dynamické vojny z mechaník
- **Tactical Space Combat** – modulárne lode, boarding akcie
- **Emergent Storytelling** – príbeh z interakcie systémov

Detaily v `docs/vision.md`.

## Inštalácia (dev)

1. Klonuj repo do Starbound `mods/` priečinka
2. Spusti Starbound s nainštalovaným Frackin' Universe modom
3. FU je tvrdá závislosť, mod nefunguje bez neho

## Vývoj

Tento projekt používa Claude Code s viacerými subagentmi.
Viď `.claude/agents/` pre definície.

### Štruktúra
- `mod/` – samotný mod (scripts, configs, objects, patches, tests)
- `docs/` – design dokumenty
- `prototypes/` – disposable prototypy a mockupy (nie sú súčasťou modu)
- `tools/` – dev nástroje (test runner)
- `.claude/` – Claude Code konfigurácia
- `CLAUDE.md` – kontext pre AI agentov

### Moduly ekonomiky (`mod/scripts/`)
| Modul | Účel | Sekcia economy docu |
|---|---|---|
| `sb2_util.lua` | clamp, round, deepCopy, require (no silent failures) | – |
| `sb2_config.lua` | načítanie JSON configov (root.assetJson, mimo hry SB2_TEST_CONFIGS) | – |
| `sb2_prng.lua` | deterministický PRNG + hash pre jitter | 3.6, otázka 4 |
| `sb2_economy_tags.lua` | coverage pravidlo, parametre itemov, drift scan | 4.3, 6.4 |
| `sb2_pricing.lua` | cenová formula, player pressure, decay, top reasons | 3.2–3.5, 5.3 |
| `sb2_market_state.lua` | per-station stav, transakcie, day tick, catch-up, breakdown | 2.1, 4.1, 5.4, 6.1–6.3 |
| `sb2_migrations.lua` | migration runner s backupom a odmietnutím novšej schémy | 4.4, 8.1 |
| `sb2_storage.lua` | backendy memory / worldProperty / playerProperty, load s migráciou | 4.1, 4.2, 8.2 |
| `sb2_station.lua` | station_id z parametra alebo world.id(), system key | influence 4.3 |
| `sb2_market_view.lua` | filter, formát riadkov a texty dôvodov pre terminál | 5.4 |
| `objects/sb2_market/` | breakdown terminál: ScriptPane (klient) + objekt (server) cez entity message | 5.2, 5.4 |

Čaká na výsledky prototypov: universe-level backend (Q1/Q2), merchant hook a day tick host (Q3, sekcia 4 analýzy).

### Testy
Čisté moduly majú standalone testy v `mod/tests/`, bežia mimo Starbound pod Lua 5.1/5.3/5.4:
```
pip install lupa
python3 tools/run_lua_tests.py
```

## Status

**Aktuálna fáza:** Pred-implementácia, prototypovanie storage vrstvy

**Hotové:**
- ✅ Project vision (`docs/vision.md`)
- ✅ Foundation (CLAUDE.md, štruktúra, architect + systems-coder agent)
- ✅ Design doc pre Dynamic Pricing System (`docs/economy-system.md`, v1 draft)
- ✅ Prototyp Q1/Q2 storage test (`prototypes/q1_q2_storage_test/`, čaká na spustenie)
- ✅ Analýza stavu a plánovaných features (`docs/planned-features-analysis.md`) + mockup v2
- ✅ Jadro DPS ako čisté Lua moduly s testami (`mod/scripts/`, `mod/tests/`)
- ✅ Prototyp Q3 merchant price test (`prototypes/q3_merchant_price_test/`, čaká na spustenie)
- ✅ Design doc frakčného vplyvu, v0.1 rozsah (`docs/influence-system.md`)
- ✅ `sb2_market` breakdown terminál (`mod/objects/sb2_market/`, čaká na in-game test)

**Najbližší míľnik:**
- ⏳ Výsledky prototypov Q1/Q2 a Q3 → universe backend, merchant hook, day tick host, `sb2_market` terminál

**Verzia:** v0.0.1

## Roadmap

- **v0.1** – Functional dynamic pricing + rules-based factions
- **v0.5** – Utility AI, modding API, example extension
- **v1.0** – Space combat, personality AI, public Lua hooks
- **v2.0+** – Faction agendas, inter-faction memory

Detaily v `docs/vision.md` (sekcia Version milestones).

## Licencia

TBD (zváži sa pred prvým release).
