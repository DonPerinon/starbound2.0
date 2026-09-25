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
- `mod/` – samotný mod (scripts, items, objects, patches)
- `docs/` – design dokumenty
- `.claude/` – Claude Code konfigurácia
- `CLAUDE.md` – kontext pre AI agentov

## Status

**Aktuálna fáza:** Pred-implementácia, prototypovanie storage vrstvy

**Hotové:**
- ✅ Project vision (`docs/vision.md`)
- ✅ Foundation (CLAUDE.md, štruktúra, architect + systems-coder agent)
- ✅ Design doc pre Dynamic Pricing System (`docs/economy-system.md`, v1 draft)
- ✅ Prototyp Q1/Q2 storage test (`prototypes/q1_q2_storage_test/`, čaká na spustenie)
- ✅ Analýza stavu a plánovaných features (`docs/planned-features-analysis.md`)

**Najbližší míľnik:**
- ⏳ Výsledky prototypu Q1/Q2 zapísané do economy docu, potom storage layer DPS

**Verzia:** v0.0.1

## Roadmap

- **v0.1** – Functional dynamic pricing + rules-based factions
- **v0.5** – Utility AI, modding API, example extension
- **v1.0** – Space combat, personality AI, public Lua hooks
- **v2.0+** – Faction agendas, inter-faction memory

Detaily v `docs/vision.md` (sekcia Version milestones).

## Licencia

TBD (zváži sa pred prvým release).
