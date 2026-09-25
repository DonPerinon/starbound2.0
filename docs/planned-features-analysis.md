# Analýza plánovaných features – stav base k 2026-09-25

Tento dokument je snapshot: čo je v repozitári hotové, čo je naplánované, ako to sedí s víziou a kde sú riziká. Nie je to design doc, nič nepredpisuje. Zdroj pravdy ostáva `docs/vision.md`.

## 1. Stav base (main @ fca05f9)

| Oblasť | Stav | Poznámka |
|---|---|---|
| Vízia (`docs/vision.md`) | hotová, v3 | 5 pillarov, roadmap v0.1 → v2.0+, success criteria |
| Foundation (`CLAUDE.md`, agenti, `mod/_metadata`) | hotová | architect + systems-coder agent, konvencie, bug triage |
| Design doc DPS (`docs/economy-system.md`) | hotový, v1 draft | 608 riadkov, formuly, schémy, edge cases, test plan, 7 otvorených otázok |
| Prototyp Q1/Q2 storage test | napísaný, **nespustený** | výsledky nie sú zapísané v sekcii 10 economy docu |
| Mockup UI (`prototypes/features-mockup.html`) | hotový | 7 obrazoviek + 10 konceptových features |
| Design doc faction influence (`docs/influence-system.md`) | **chýba** | v0.1 ho potrebuje (dummy rules-based AI) |
| Sub-design `docs/trade-flow-v01.md` | chýba (zámerne, vznikne pri implementácii) | |
| Produkčný kód v `mod/` | **0 riadkov** | iba `_metadata` |
| `KNOWN_ISSUES.md`, licencia | chýbajú | licencia TBD pred prvým release |

Časová os: vízia, foundation, DPS design aj prototyp vznikli za jeden deň (2026-05-24). Potom 4 mesiace ticho. Dnešný commit „sa“ iba nahral tú májovú prácu na GitHub. Fáza projektu je stále **Setup (pred-implementácia)**, presne tak, ako to bolo v máji.

Status riadky v `CLAUDE.md`, `README.md` a `vision.md` sú zastarané: všetky tri uvádzajú ako najbližší míľnik „Design doc pre DPS“, ktorý už existuje.

## 2. Čo je naplánované

### 2.1 Roadmap podľa vision.md

- **v0.1** – Dynamic Pricing System + dummy rules-based frakčná AI + data-driven JSON. Žiadny combat.
- **v0.5** – utility AI vrstva, `docs/MODDING.md`, stabilné JSON schémy, example extension mod.
- **v1.0** – modulárny vesmírny combat + boarding, personality modifiers, public Lua hooks.
- **v2.0+** – goals/agendas, inter-faction memory, prípadne Workshop.

### 2.2 Desať konceptových features z mockupu

Mockup pridáva 10 konceptov nad rámec vízie. Nie sú v žiadnom design docu ani v roadmape vision.md, existujú iba v HTML prezentácii. Hodnotenie je v sekcii 5.

## 3. Pripravenosť na v0.1

v0.1 je dosiahnuté až keď platí všetko v definícii. Rozpad na kusy práce:

| Kus práce | Design | Kód | Blokuje ho |
|---|---|---|---|
| Storage layer (per-station `world.setProperty`, universe state) | navrhnutý, sekcia 4 | nie | **výsledok prototypu Q1/Q2** |
| `sb2_prng.lua` (deterministický jitter) | otvorená otázka 4 | nie | nič, dá sa začať hneď |
| `sb2_economy_tags.config` + coverage pravidlo | navrhnuté, sekcia 4.3 | nie | overenie FU tagov na reálnych itemoch |
| Day tick `sb2_economy_day` | navrhnutý, sekcia 2.1 | nie | rozhodnutie KDE beží (viď 4.3) |
| Merchant hook (ceny + top_reasons) | navrhnutý, sekcia 5.1 | nie | **overenie, že je vôbec možný** (viď 4.1) |
| `sb2_market.object` breakdown terminál | navrhnutý, sekcia 5.2 | nie | nič, ScriptPane je overený prototypom |
| Migration framework + fixtures | navrhnutý, sekcia 4.4, 8 | nie | storage layer |
| Debug príkazy `/sb2_debug_market` | navrhnuté, sekcia 9.2 | nie | Starbound nemá custom chat príkazy z Lua, treba iný vstup (terminál, item) |
| Dummy frakčná AI (rules-based) | **žiadny design doc** | nie | `docs/influence-system.md` |
| Trade flow scheduler | zámerne odložený | nie | `docs/trade-flow-v01.md` |

Záver: pre v0.1 chýba jeden celý design doc (influence) a jeden sub-design (trade flow). Ekonomika je designovo pripravená, ale stojí na dvoch technických predpokladoch, ktoré nie sú overené (sekcia 4).

## 4. Technické riziká voči Starbound enginu

Nemôžem spustiť Starbound, takže toto sú tvrdenia z mojej znalosti Starbound 1.4 Lua API a FU. Každé treba overiť prototypom skôr, ako sa naň postaví kód. Zoradené podľa dopadu.

### 4.1 Merchant UI je C++ pane, nie Lua skript (dopad: vysoký)

Design doc počíta s `merchant.lua.patch` a s tooltipom, do ktorého sa pridajú 3 riadky dôvodov. Vanilla merchant okno (`MerchantPane`) je podľa mojich znalostí implementované v C++ a nie je skriptovateľné. Cena položky v okne vzniká ako `item.price × buyFactor` z konfigurácie, ktorú NPC odovzdá pri `OpenMerchantInterface` interakcii. FU tento pane nenahrádza.

Čo z toho plynie:

- **Cenu per item zmeniť ide**, ale nie hookom vo UI. Ide to cez interact config NPC merchanta (položka v zozname `items` môže niesť vlastnú `price`). Single point patch teda nie je `merchant.lua`, ale miesto, kde NPC skladá svoj item list (vanilla merchant behavior skript / `interactAction`). To stále spĺňa princíp jedného hooku, iba na inej vrstve.
- **Tooltip s dôvodmi je problém.** Tooltip v merchant okne je štandardný item tooltip. Jediná cesta, ktorú poznám, je zapísať dôvody do `parameters.description` položky (hack, ktorý mení item instance a môže rozbiť stackovanie). Realistická alternatíva: dôvody ukazovať iba v `sb2_market` termináli a v merchant okne len cenu.
- Success criterion „každá dynamická cena má v UI viditeľný dôvod“ je tým ohrozené v doslovnom znení. Odporúčam ho preformulovať na „dôvod je dostupný na jedno kliknutie na stanici“, kým prototyp neukáže inak.

Odporúčanie: prototyp č. 3 – NPC merchant s override ceny per item + pokus o description hack. Bez toho nemá zmysel písať `sb2_economy_compute_price`.

### 4.2 `world.setProperty` je per-world, universe state nemá kam ísť (dopad: vysoký)

Prototyp Q1/Q2 to má overiť. Moje očakávanie výsledku:

- `world.setProperty` je scope **per-world** (ukladá sa do metadát daného sveta). Pre per-station market state je to v poriadku, stanica žije na svojom svete.
- `io.*` je v Starbound Lua sandboxe **nedostupné**, `root.assetJson` je **read-only**. Súbor `storage/sb2_economy_global.json` z sekcie 4.2 economy docu teda podľa mňa nie je možné zapísať.

Kde universe state môže bývať:

- `player.setProperty` – perzistentné v player súbore, dostupné z player generic script contextu, cestuje s hráčom medzi svetmi. Pre singleplayer ideálne.
- Ship world hráča – vždy načítaný počas hry, `world.setProperty` na ňom funguje, ale iné svety ho nevidia.

Dôsledok pre co-op: universe state na hostovom hráčovi nevidia klienti priamo. Sync musí ísť cez svet, na ktorom sú obaja (world property alebo `world.sendEntityMessage` na player entity). Sekcia 6.5 economy docu („host je jediný writer, klienti dostávajú push cez universe state sync“) predpokladá kanál, ktorý engine neposkytuje. Treba ho navrhnúť explicitne, alebo co-op determinizmus v v0.1 vypustiť zo success criteria.

### 4.3 Skripty bežia iba na načítaných svetoch (dopad: stredný)

„Galaxia žije aj keď sa nepozerám“ sa nedá dosiahnuť simuláciou na pozadí. Day tick musí bežať v niečom, čo je vždy načítané: player generic script context (`player.config` → `genericScriptContexts`) alebo skript na ship worlde. Stanice, ktoré hráč nevidí, sa doháňajú lazy pri návšteve (sekcia 6.1 to už rieši batch decayom). Design toto implicitne predpokladá, ale nikde neurčuje domov day ticku. Odporúčam player generic script context, lebo má zároveň `player.setProperty` pre universe state.

### 4.4 Custom chat príkazy z Lua neexistujú (dopad: nízky)

`/sb2_debug_market`, `/sb2_run_migration_tests`, `/sb2_cleanup_backups` sa z modu registrovať nedajú. Prototyp Q1/Q2 to už obišiel ScriptPane terminálom (používateľ zakázal `/run` a `/eval`). Rovnaký vzor stačí pre debug: druhá záložka v `sb2_market` termináli alebo samostatný `sb2_debug_terminal` object.

### 4.5 Starmap nie je skriptovateľná (dopad: stredný, až v0.5+)

Mockup Screen 03 kreslí sféry vplyvu do galaktickej mapy. Navigačný pane je C++. Mapa vplyvu bude musieť byť vlastný ScriptPane s `canvas` widgetom a vlastným vykreslením systémov. Realizovateľné, ale je to vlastné UI od nuly, nie overlay. Treba to vedieť pri odhade v0.5.

### 4.6 Tactical Space Combat: najlepšia cesta je mech framework (dopad: rozhoduje o v1.0)

Vízia hovorí „žiadny vlastný engine“ a súčasne chce real-time 2D arénu s modulárnymi loďami. Jediné, čo Starbound natívne ponúka, sú space encounter instance worldy s nulovou gravitáciou a modulárny mech (`vehicles/modularmech`: telo, ruky, nohy, booster ako JSON party s vlastným HP a energiou). To sedí s mockupom Screen 06 (weapon / shield / system / engine sloty) takmer jedna k jednej. Boarding = dokovanie na nepriateľskú loď = vstup do dungeon instance, čo vanilla space encounters už robia.

Odporúčanie: v design docu pre combat (v1.0) vychádzať z mech frameworku a space encounters, nie z vlastnej „lode ako entity“. Inak v1.0 porušuje vlastný out of scope.

## 5. Hodnotenie desiatich konceptových features

Kritériá: fit s víziou (pillary, out of scope), technická náročnosť v Starbound enginu, závislosti na iných systémoch, odporúčaná verzia.

| # | Feature | Fit | Náročnosť | Závisí na | Odporúčanie |
|---|---|---|---|---|---|
| 01 | Trade Route Planner | výborný (transparent depth, trader) | nízka, čistý ScriptPane nad existujúcimi dátami | DPS + trade flows | v0.5 ako v mockupe |
| 02 | Dynamic Contract Board | dobrý, ale hranica s „žiadne procedurálne questy“ je tenká | stredná | faction state + economy events | v0.5, iba ak sú kontrakty čisto template z existujúcich eventov, bez quest generátora |
| 03 | Player Trade Post | výborný (builder, vizuálny progress) | stredná: nový market node = nová stanica v `known_stations` | DPS storage, trade flows | v1.0; blokované rozhodnutím o universe state |
| 04 | Price History Ticker | výborný, priamo podporuje success criteria | nízka, ale rastie storage per stanica (história × items) | DPS | v0.5; treba limit histórie (napr. 14 dní) kvôli veľkosti world property |
| 05 | Faction Standing & Perks | dobrý (strategy fanúšik) | nízka až stredná | influence system | v0.5; pozor, vanilla aj FU majú vlastné reputačné mechaniky, neduplikovať |
| 06 | Blockade Running | výborný, spája economy a combat | vysoká, potrebuje interdikciu = combat | combat v1.0 | v1.0, nie skôr |
| 07 | Regional Heat & Pirate Threat | výborný, emergentný zo systémov | nízka bez combatu (iba číslo + modifikátor), vysoká s pirátskymi entitami | influence + DPS | v0.5 iba ako abstraktný modifikátor; entity až v1.0 |
| 08 | NPC Base Raids | dobrý, ale hrozí scope creep (pozemný boj, base defense) | vysoká | influence + FU base mechaniky | v1.0 alebo neskôr; navrhujem odložiť za v1.0 |
| 09 | Crew Roster & Officers | stredný, vanilla crew systém už existuje | stredná | combat | v1.0; rozšíriť vanilla crew, nie nový systém |
| 10 | Insurance & Salvage Market | dobrý, uzatvára risk loop | stredná | trade flows + combat straty | v1.0, potrebuje reálne straty konvojov |

Súhrn: tri z desiatich (01, 04, 07 v abstraktnej forme) sú lacné a priamo posilňujú v0.5. Päť (03, 06, 08, 09, 10) stojí na combate a nemajú zmysel pred v1.0. Feature 08 je jediná, ktorá podľa mňa ohrozuje disciplínu scope. Feature 02 treba strážiť voči out of scope „žiadne procedurálne questy“.

Ani jedna z desiatich nie je v vision.md. Ak majú platiť, patria do sekcie Version milestones, inak ostanú ako inšpirácia bez záväzku.

## 6. Nekonzistencie v repozitári

- **`mod/_metadata` používa `includes` namiesto `requires`.** `includes` je mäkká závislosť (načítaj po FU, ak existuje). Vízia aj economy doc hovoria, že bez FU má mod padnúť pri načítaní. To robí `requires`. Priamy rozpor s pravidlom „no silent failures“.
- `mod/_metadata` má `author: "Tvoje meno"` (placeholder).
- Status v `CLAUDE.md`, `README.md`, `vision.md` uvádza ako ďalší míľnik hotový DPS design doc.
- `.claude/agents/*.md` obsahujú absolútnu cestu `/home/rastislav-pobis/...` pre agent memory. Na inom stroji (aj v tejto cloud session) neplatí.
- Prototyp Q1/Q2 je v repozitári, ale README prototypu hovorí „mod VYMAZAŤ po skončení testovania“. Výsledky testov nie sú nikde. Buď sa prototyp nespustil, alebo sa výsledok nezapísal.
- Economy doc sekcia 4.2 predpokladá zápis súboru, sekcia 8.2 predpokladá file backupy. Obe stoja na otvorenej otázke 2, ktorá zatiaľ nemá odpoveď.
- `docs/influence-system.md` je v `CLAUDE.md` označený ako „chýba“ a stále chýba, hoci v0.1 vyžaduje frakčnú AI.

## 7. Odporúčané poradie ďalších krokov

1. **Spustiť prototyp Q1/Q2 a zapísať výsledky** do economy docu sekcie 10. Kým nie je jasné, kam ide universe state, nemá zmysel písať storage layer.
2. **Prototyp č. 3: merchant price override.** Overiť, či NPC merchant zoberie per-item `price` z interact configu a či sa dá do tooltipu dostať text. Rozhodne o sekcii 5.1 a 5.3 economy docu.
3. **Revízia economy docu v2** podľa výsledkov 1 a 2: sekcia 4.2 (universe state), 5.1 (hook), 5.3 (tooltip), 6.5 (co-op sync), 9.2 (debug bez chat príkazov). Určiť domov day ticku.
4. **Opraviť `mod/_metadata`** (`requires`, author) a status riadky v troch dokumentoch. Malá zmena, ale odstráni prvý rozpor s vlastnými pravidlami.
5. **`docs/influence-system.md`** aspoň pre v0.1 rozsah (rules-based, read-only voči ekonomike). Bez neho v0.1 nie je dosiahnuteľné.
6. Až potom prvý produkčný kód: `sb2_prng.lua` (nezávislý od všetkého, má jasnú špecifikáciu) a storage layer.
7. Rozhodnúť o 10 konceptových features: buď ich zapísať do vision.md Version milestones s verziou z tabuľky v sekcii 5, alebo ich označiť ako nezáväzné.

## Status

- **Dátum**: 2026-09-25
- **Analyzovaný commit**: `fca05f9` na `main`
- **Typ**: jednorazová analýza, neaktualizuje sa
