# SB2 Q1/Q2 Storage Test – Prototype Mod

## 1. Ucel

Tento **disposable prototype mod** overuje dve technicke otazky z `docs/economy-system.md` sekcia 10 (Otvorene otazky):

**Q1 (otazka 1):** Ma `world.setProperty` v Starbound Lua API hard limit pre velkost stringu?
Ak ano (napr. 64 KB), per-station market state s 30+ items by mohol narazit. Treba zistit limit a ci je scope per-world alebo universe.

**Q2 (otazka 2):** Ake metody atomic file write su dostupne v Starbound Lua sandboxe?
Treba zistit ci `root.assetJson` / asset API vie zapisovat, ci `io.*` je dostupne, alebo musime ist cez `world.setProperty` na placeholderovom worlde.

Vysledky rozhodnu o architektare universe-level state (sekcia 4.2 economy-system.md).

**Mod VYMAZAT po skonceni testovania – nie je production kod.**

---

## 2. Instalacia

Skopiruj priecinok `q1_q2_storage_test/` ako celok do Starbound mods/ adresara pod nazvom `sb2_q1_q2_storage_test`:

**Linux (Steam):**
```
~/.local/share/Steam/steamapps/common/Starbound/mods/sb2_q1_q2_storage_test/
```

**Windows (Steam):**
```
C:\Program Files (x86)\Steam\steamapps\common\Starbound\mods\sb2_q1_q2_storage_test\
```

Struktura po instalacii:
```
mods/
  sb2_q1_q2_storage_test/
    _metadata
    README.md
    objects/
      sb2_test_terminal/
        sb2_test_terminal.object
        sb2_test_terminal.config
        sb2_test_terminal.lua
        sb2_test_terminal.png
    scripts/
      sb2_test_world_property.lua
      sb2_test_atomic_write.lua
```

---

## 3. Predpoklady

- Starbound spusteny v `/admin` mode (nutne pre `/spawnitem`)
- **FU nie je potrebne** – mod nema ziadne dependencies
- Existujuci save odporucany (testujeme world.setProperty, ciste prostredie znizi sank)
- Linux: `/tmp/` musi byt zapisatelne (pre Q2 io.* test, standardne je)

---

## 4. Test postup – presne kroky

### Krok 1 – Spusti Starbound, nacitaj save

Spusti Starbound, nacitaj lubovolny save (odporucany existujuci save na planete, nie ship).

### Krok 2 – Spawn terminaloveho objektu

Otvor chat konzolu (`/` alebo Enter) a spusti:

```
/admin
```

```
/spawnitem sb2_test_terminal
```

Objekt sa objavi v tvojom inventari. Poloz ho na zem (ako normalny item). Pristup k nemu stlacenim `E`.

Otvori sa panel "SB2 Storage Test Terminal" so 8 tlacidlami a status riadkom "Status: READY".

### Krok 3 – Q1 size sweep + LOGTRUNC probe

Klikni tlacidlo **[1] Q1: Run size sweep (1KB-5MB)**.

Status sa zmeni na "Running..." a po dokonceni zobrazí vysledok. Vsetky detaily su v logu (pozri sekciu 5).

Sleduj riadky `[SB2_TEST_Q1]` v starbound.log.

### Krok 4 – Q1 Cross-world scope test (4 kroky)

Toto je postupny test – kazdy krok sa vola z ineho sveta:

1. **Na aktualnom svete (planeta A):** klikni tlacidlo **[2] Q1 X-world: Write marker HERE**.
   - Log potvrdí "Step 1 DONE. Marker 'world_A_value' written."

2. **Warpni na UPLNE INY svet** (ship, outpost, ina planeta – lubovolny svet).
   - Interaguj s terminalom znova (E) ak si preniesol objekt, alebo pouzi druhy umiestneny terminal.
   - Klikni **[3] Q1 X-world: Read marker (after warp)**.
   - Log ukazuje ci je marker viditelny na inom svete (PRELIMINARY verdict).

3. **Stale na inom svete:** klikni **[4] Q1 X-world: Overwrite marker**.
   - Log potvrdí "Step 3 DONE. Marker 'world_B_value' written."

4. **Warpni SPAT na povodnu planetu (svet A).**
   - Interaguj s terminalom na svete A.
   - Klikni **[5] Q1 X-world: Verify (after warp back)**.
   - Log vypise `WORLD_PROPERTY_SCOPE: per-world | universe | undefined`.

### Krok 5 – Q2 atomic write tests

Klikni tlacidlo **[6] Q2: Run atomic write tests**.

Test prebehne automaticky vsetky 3 sub-testy:
- root.assetJson write probe
- io.* sandbox probe (pokusi sa zapist /tmp/sb2_test_atomic.txt)
- chunked world.setProperty round-trip (2x 25 KB chunk)

Na konci Q2 vypise tabulku `atomic write methods comparison` a `RECOMMENDATION`.

### Krok 6 – Q2 chunk reload test

Po kliknuti [6] je crash simulacia uz vykonana (chunk1 = "CRASH_SIMULATION_VALUE", chunk2 = predosla hodnota).

Teraz **reloadni save** (ukoncit hru, znovu nacitat save, ALEBO prikaz `/reload` ak dostupny).

Po reloade: interaguj s terminalom, klikni **[7] Q2: Check chunks after reload**.

Log ukaze `CHUNK_RELOAD: CONFIRMED partial persistence | both chunks empty | mixed state`.

### Krok 7 – Cleanup

Klikni **[8] Reset all markers + cleanup**.

Toto zmaze vsetky `sb2_test_*` world properties na aktualnom svete. Status ukazuje pocet uspesne vymazanych a failnutych klucon.

---

## 5. Kde najst log

**Linux:**
```
~/.local/share/Steam/steamapps/common/Starbound/storage/starbound.log
```

**Windows:**
```
C:\Program Files (x86)\Steam\steamapps\common\Starbound\storage\starbound.log
```
(alebo `%APPDATA%\StarboundStarbound\storage\starbound.log` podla verzie Steam)

Hladas riadky s prefixom `[SB2_TEST_Q1]`, `[SB2_TEST_Q2]`, `[SB2_TERMINAL]`.

**Log truncation probe (LOGTRUNC_PROBE):**
1. Hladaj riadok `[SB2_TEST_Q1] LOGTRUNC_PROBE: ABCDEFGH...` v logu.
2. Zmer dlzku tohto riadku v textovom editore (napr. `wc -m` na Linuxe).
3. Porovnaj s riadkom `[SB2_TEST_Q1] LOGTRUNC_PROBE: expected line length = XXXX`.
4. Ak je dlzka v logu kratsia ako expected -> log je skratovany.
5. Potom najdi `[SB2_TEST_Q1] LOGTRUNC_PROBE: end-marker` – overi ze aj tento riadok existuje.

---

## 6. Expected output format – sablona

### Q1 size sweep (idealne vsetky PASS do nejakeho limitu):

```
[SB2_TEST_Q1] ========================================
[SB2_TEST_Q1] world.setProperty size sweep
[SB2_TEST_Q1] ========================================
[SB2_TEST_Q1] World type: terrestrial
[SB2_TEST_Q1]    1 KB -> write: OK | read: OK | integrity: PASS
[SB2_TEST_Q1]   10 KB -> write: OK | read: OK | integrity: PASS
[SB2_TEST_Q1]   50 KB -> write: FAIL (pcall err: ...)
[SB2_TEST_Q1]  100 KB -> write: FAIL (pcall err: ...)
[SB2_TEST_Q1] LIMIT DETECTED between 10 KB and 50 KB
[SB2_TEST_Q1] NIL_BEHAVIOR: delete OK (key removed)
[SB2_TEST_Q1] LOGTRUNC_PROBE: ABCDEFGH... (10240 znakov)
[SB2_TEST_Q1] LOGTRUNC_PROBE: end-marker (user must verify previous line in log file)
[SB2_TEST_Q1] CLEANUP: sb2_test_prop_1kb via nil
...
[SB2_TEST_Q1] runSizeTest COMPLETE.
```

### Q2 zaverecna tabulka (priklad):

```
[SB2_TEST_Q2] ========================================
[SB2_TEST_Q2] atomic write methods comparison
[SB2_TEST_Q2]  (a) root.assetJson write : unavailable
[SB2_TEST_Q2]  (b) io.* sandbox         : blocked (io table nil or io.open fails)
[SB2_TEST_Q2]  (c) chunked setProperty  : see log above (PASS/FAIL per line)
[SB2_TEST_Q2] RECOMMENDATION: io.* is blocked. Use chunked world.setProperty...
[SB2_TEST_Q2] ========================================
```

---

## 7. Cleanup

**Automaticky cleanup:** tlacidlo [8] vymaze vsetky `sb2_test_*` world properties na aktualnom svete.

**Manualny cleanup** (ak [8] zlyhalo alebo bol test preruseny):
- Otvor konzolu a spusti pre kazdy kluc ktory zlyhal podla logu:
  ```
  /admin
  /entityeval world.setProperty("sb2_test_prop_1kb", nil)
  ```
  (opakuj pre kazdy kluc zo zoznamu v `scripts/sb2_test_world_property.lua`, riadky SB2_TEST_KEYS)

**Temp subor** (ak `io.*` fungoval):
```
rm /tmp/sb2_test_atomic.txt
```

**Odinstalovanie modu:**
1. Vymaz priecinok `sb2_q1_q2_storage_test/` z `mods/`.
2. Pre vymaz objektu zo sveta: interaguj s nim a pouzi pickaxe / matter manipulator, alebo:
   ```
   /admin
   /entityeval entity.smash()
   ```
   (Stoj tesne pri objekte – `/entityeval` vola na blizku entity.)

---

## 8. Interpretacia vysledkov

| Vysledok testu | Dosledok pre DPS architekturu |
|---|---|
| Q1: limit < 50 KB | Per-station market state treba rozdelit do viacerych klucon (napr. per kategoria itemov) |
| Q1: limit >= 50 KB | 13 KB per market state (30 items, odhadnute v sekcia 7.2 economy-system.md) pohodlne zmesti |
| Q1: scope = per-world | Universe-level state (global modifiers, trade flows) NEMOZE ist cez world.setProperty – treba file alebo ship-world trick |
| Q1: scope = universe | world.setProperty moze sluzit ako universe storage (overit na roznych world typoch) |
| Q2: io.* funguje | Preferuj io.open + write-to-tmp + rename pattern pre universe-level state (atomicke) |
| Q2: io.* blocked | Nutne chunks cez world.setProperty, alebo vyskumat ship-world ako perzistentny placeholder |
| Q2: root.assetJson write OK | Mozna alternativa pre male JSON config suborov (ale pravdepodobne len read-only) |
| Q2: chunked WSP PASS + scope = per-world | Universe state nemozno ulozit per-world -> iny pristup nutny |

**Doporucene akcie po testovani:**
1. Zaznamenat presne limity do `docs/economy-system.md` sekcia 10 (aktualizacia otazenych otazok 1 a 2).
2. Podla vysledkov aktualizovat sekcie 4.1 a 4.2 – ci zostava per-world alebo treba universe storage refactor.
3. Vymazat tento prototype mod z mods/.
