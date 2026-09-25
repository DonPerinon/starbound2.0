# SB2 Q3 Merchant Price Test – Prototype Mod

## 1. Ucel

Tento **disposable prototype mod** overuje predpoklad z `docs/economy-system.md` sekcia 5.1 a 5.3 a riziko 4.1 z `docs/planned-features-analysis.md`: merchant okno v Starbounde je C++ pane, nie Lua skript. DPS potrebuje vediet, ako sa da do neho dostat dynamicka cena a dovod ceny.

Tri otazky:

**Q3a – per-item price override:** Berie merchant pane hodnotu `price` z jednotlivych poloziek v `items` zozname? Ak ano, cena sa da nastavit bez patchovania UI.

**Q3b – dynamicky config z Lua:** Da sa merchant config zostavit v `onInteraction()` skripte objektu pri kazdom otvoreni? Ak ano, DPS moze cenu pocitat v momente otvorenia (lazy on-read podla sekcie 2.1).

**Q3c – dovod ceny v tooltipe:** Zobrazi sa text z `parameters.description` polozky v tooltipe merchant okna? Ak ano, "top 3 dovody" sa daju ukazat bez patchu UI (za cenu, ze polozka nesie vlastne parametre).

**Q3d – vanilla NPC merchant (investigacia, bez kodu):** Kde v unpacked assets NPC sklada `OpenMerchantInterface` config? To urci, kde bude single point hook pre vanilla a FU merchantov.

**Mod VYMAZAT po skonceni testovania – nie je production kod.**

---

## 2. Instalacia

Skopiruj priecinok `q3_merchant_price_test/` ako celok do Starbound `mods/` adresara pod nazvom `sb2_q3_merchant_price_test`.

**Linux (Steam):** `~/.local/share/Steam/steamapps/common/Starbound/mods/sb2_q3_merchant_price_test/`
**Windows (Steam):** `C:\Program Files (x86)\Steam\steamapps\common\Starbound\mods\sb2_q3_merchant_price_test\`

Struktura:
```
mods/sb2_q3_merchant_price_test/
  _metadata
  README.md
  objects/
    sb2_test_shop_static/
      sb2_test_shop_static.object
      sb2_test_shop_static.png
    sb2_test_shop_dynamic/
      sb2_test_shop_dynamic.object
      sb2_test_shop_dynamic.lua
      sb2_test_shop_dynamic.png
```

FU nie je potrebne. Starbound spusteny v `/admin` mode (pre `/spawnitem`).

---

## 3. Test postup

### Krok 1 – Q3a + Q3c (staticky shop)

```
/admin
/spawnitem sb2_test_shop_static
```

Poloz objekt, stlac `E`. Otvori sa merchant okno so 4 riadkami. Zapis do tabulky v sekcii 4:

| Riadok | Ocakavana cena ak override funguje | Co vidis |
|---|---|---|
| Liquid Water (bez `price`) | vanilla default (referencia) | |
| Liquid Water (`price: 4`) | 4 | |
| Titanium Bar (`price: 16`) | 16 | |
| Core Fragment (`price: 64`) | 64 | |

- Ak druhy riadok Liquid Water ukazuje inu cenu ako prvy → **Q3a = PASS**.
- Ak obidva ukazuju rovnaku vanilla cenu → **Q3a = FAIL**, per-item `price` sa ignoruje.

Prejdi mysou na Core Fragment. Ak tooltip ukazuje tri farebne riadky "+30% Blokada Apexov..." → **Q3c = PASS**. Ak ukazuje povodny popis Core Fragmentu → **Q3c = FAIL**.

Skus kupit Core Fragment. Skontroluj v inventari, ci kupena polozka nesie upraveny popis (bude sa stackovat oddelene od beznych Core Fragmentov – to je znamy vedlajsi efekt description hacku, zapis ci sa to stalo).

### Krok 2 – Q3b (dynamicky shop)

```
/spawnitem sb2_test_shop_dynamic
```

Poloz, stlac `E`. Zatvor okno, stlac `E` znova, opakuj 3x. Ceny by mali rast o 10 % base za kazde otvorenie (Liquid Water: 6, 6, 7, 7...; Core Fragment: 33, 36, 39, 42).

- Ak sa okno otvori a ceny rastu → **Q3b = PASS**.
- Ak sa okno neotvori → **Q3b = FAIL**, `onInteraction` nevie vratit `OpenMerchantInterface`. Skontroluj log na chybu.
- Ak sa otvori, ale ceny sa nemenia → Q3a FAIL potvrdeny druhou cestou.

V logu hladaj riadky `[SB2_TEST_Q3]`.

### Krok 3 – Q3d (investigacia v unpacked assets)

V rozbalenych vanilla assets (`asset_unpacker packed.pak <dir>`) spusti:

```
grep -rl "OpenMerchantInterface" npcs/ scripts/ interface/ objects/ | head -20
```

Zapis:
1. Ktory NPC skript vracia `OpenMerchantInterface` a ako sklada `items` (z `merchantpools.config`? z `scriptConfig.merchant`?).
2. Ci je tam miesto, kde sa da polozkam nastavit `price` (hladaj `price` v tom subore).
3. To iste v rozbalenom FU (`FrackinUniverse/npcs/`, `FrackinUniverse/scripts/`) – ci FU tento skript prepisuje.

---

## 4. Vysledky (vyplnit)

| Otazka | Vysledok | Poznamka |
|---|---|---|
| Q3a per-item price | PASS / FAIL | |
| Q3b dynamic config z Lua | PASS / FAIL | |
| Q3c description v tooltipe | PASS / FAIL | stackovanie: |
| Q3d NPC hook miesto | cesta k suboru + funkcia | FU override: ano / nie |

---

## 5. Interpretacia

| Vysledok | Dosledok pre DPS |
|---|---|
| Q3a PASS + Q3b PASS | Hook = miesto, kde sa sklada `items` zoznam. Sekcia 5.1 economy docu prepisat z "merchant.lua patch" na "merchant config builder hook". |
| Q3a FAIL | Cenu nejde nastavit per item. Zostava iba `buyFactor` per merchant (jedna cena pre vsetko) – DPS musi byt redesignovany na per-station multiplikator, nie per-item. Velky dopad. |
| Q3c PASS | Top 3 dovody v tooltipe su realne. Rozhodnut, ci akceptujeme oddelene stackovanie kupenych poloziek, alebo dovody ukazovat len v `sb2_market` termináli. |
| Q3c FAIL | Sekcia 5.3 economy docu skrtnut, dovody idu vyhradne do `sb2_market` terminalu. Success criterion "kazda cena ma v UI dovod" preformulovat. |
| Q3d: FU prepisuje NPC merchant skript | Hook musi ist cez patch FU verzie skriptu, nie vanilla – zvysuje riziko pri FU update. |

Po testovani: vysledky zapisat do `docs/economy-system.md` (nova otvorena otazka 8 alebo aktualizacia sekcie 5), potom mod vymazat.

---

## 6. Cleanup

1. Znic oba objekty (matter manipulator).
2. Vymaz priecinok `sb2_q3_merchant_price_test/` z `mods/`.
3. Ak si kupil Core Fragment s upravenym popisom, vyhod ho – nesie testovacie parametre.
