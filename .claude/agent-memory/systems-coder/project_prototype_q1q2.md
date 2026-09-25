---
name: Q1/Q2 storage test prototype
description: Disposable prototype mod was implemented to answer two open questions from economy-system.md section 10
type: project
---

Prototype mod `prototypes/q1_q2_storage_test/` was implemented (2026-05-24) to answer:
- Q1: world.setProperty size limit and cross-world scope
- Q2: Available atomic file write methods in Lua sandbox (root.assetJson, io.*, chunked WSP)

**Architecture (2026-05-24 refactor):** Terminal-only variant C. Entry point is a placeable ScriptPane object (`objects/sb2_test_terminal/`) – no /run, no /eval. User spawns via `/spawnitem sb2_test_terminal`, interacts with E, clicks 8 buttons. All test logic stays in `scripts/` (unchanged), terminal.lua only delegates.

**Key implementation decisions:**
- `require` in ScriptPane context uses asset-root absolute paths (e.g. `/scripts/sb2_test_world_property.lua`)
- Global tables `sb2TestWorldProperty` / `sb2TestAtomicWrite` are set by the scripts themselves (not via return value), so terminal.lua reads them from `_G[]` after require
- ScriptPane config key is `"script"` (singular), not `"scripts"` (plural)
- Button callbacks are plain global functions in the script file (button1, button2, ...), matched by `"callback"` field in config

**Why:** User explicitly banned /run and /eval as entry points. Terminal is the only interaction method.

**How to apply:** When implementing the actual DPS storage layer, first check if this prototype was run and what results were logged. Results go back into docs/economy-system.md section 10 as resolved questions.
