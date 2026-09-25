# Vision – Starbound 2.0 (FU Extension Mod)

## Elevator pitch
Starbound 2.0 je nadstavba pre Starbound + Frackin' Universe, ktorá premieňa galaxiu z kulisy na živý systém: ceny reagujú na ponuku a dopyt, frakcie si delia územie a obchodné cesty, a stretnutia vo vesmíre sa rozhodujú modulárnymi loďami a boarding akciami. Cieľová skupina sú hráči, ktorí už majú stovky hodín v FU a chýba im strategická vrstva medzi planétami v štýle Stellaris, EVE Online a X4.

## Core pillars

### 1. Living Economy
Ceny komodít nie sú statické tabuľky – sú výsledkom local supply/demand modelu jednotlivých staníc a planét, ovplyvneného produkciou, spotrebou a hráčskymi (aj NPC) konvojmi. Hráč profituje keď číta trh, nie keď grindi rovnakú slučku. Každá dynamická cena musí v UI ukazovať dôvod (napr. `+30% blokáda Apexov`), aby trh bol čitateľný a predvídateľný, nie čierna skrinka.

### 2. Faction Influence
Frakcie (vanilla + FU) majú merateľný vplyv na sektoroch v podobe sfér vplyvu, ktoré rastú a strácajú sa cez kontrolu trade hubov, vojenskú prítomnosť a hráčske akcie. Vojny a aliancie sa spúšťajú dynamicky z týchto stavov, nie zo skriptovaných questov. Frakčná AI musí byť čitateľná – hráč vidí aktuálny stav frakcie, jej motiváciu a plánovanú akciu.

### 3. Tactical Space Combat
Vesmírne stretnutia prebiehajú v real-time 2D arénach s modulárnymi loďami (trup + sloty pre zbrane/štíty/systémy), kde má každý modul HP, energetický odber a poškoditeľnosť. Boarding je samostatná fáza – pristátie a vyriešenie boja s posádkou v existujúcom Starbound combat engine.

### 4. Emergent Storytelling
Príbeh nevzniká z dialógov, ale z konfliktu systémov: blokáda spôsobí hladomor → cena potravín vyletí → konvoje sa stanú cieľom pirátov → frakcia vyhlási vojnu. Mod dodáva mechaniky, hráč si píše vlastný príbeh.

### 5. FU-Native Integration
Všetko (suroviny, frakcie, planéty) stavia na existujúcich FU dátach. Mod nie je paralelný svet – je to vrstva nad FU, ktorá rešpektuje jeho balans, item poole a progression.

## Design principles

- **FU compatibility first** – mod nikdy nepretvára FU mechaniky, iba ich rozširuje cez JSON patche (RFC 6902); ak FU funkciu už má, použijeme ju, aby update FU nezlomil mod.
- **Performance over features** – cieľ <1ms per entity tick je tvrdý strop; feature ktorá ho prekročí sa buď redizajnuje, alebo zahodí, lebo Starbound engine na Lua 5.1 nemá rezervu na ťažké výpočty každý frame.
- **Design before code** – každý netriviálny systém má design doc v `docs/` skôr ako vznikne Lua, aby sme predišli scope creepu a kolíziám s FU.
- **Local computation, global effects** – výpočty bežia per-stanica/per-planéta a propagujú sa lazy (pri návšteve, pri obchode), nie globálne každý tick; inak galaxia s desiatkami systémov zabije TPS.
- **Player legibility** – ak hráč nevidí dôvod prečo cena stúpla alebo prečo frakcia útočí, mechanika je rozbitá; každý dynamický stav musí mať čitateľný UI feedback.
- **Data-driven content (modding-ready)** – nové komodity, frakcie, lode a moduly sa pridávajú cez JSON, nie cez Lua. JSON schémy sú od dňa 1 navrhované ako stabilný kontrakt pre tretie strany, nie ako interný implementačný detail. Logika v Lua, dáta v JSON – disciplína platí od prvého commitu.
- **Transparent depth** – mechaniky sú zámerne hlboké a komplexné, ale ich efekty sú vždy čitateľné. Hráč nemá hádať čo sa deje, len ako to využiť a kam to bude eskalovať. Komplexita vzniká z interakcie systémov (ekonomika ↔ vplyv ↔ combat), nie z opacitných čiernych skriniek. Referencia: Factorio/Stellaris (vidíš vzorce, predvídaš následky), nie Dwarf Fortress (mechaniky sa odhaľujú reverse-engineeringom). Príklady: cena ukazuje dôvod (`+30% blokáda Apexov`), frakčná AI ukazuje stav/motiváciu/plánovanú akciu. Hĺbka je v predvídaní kaskád, nie v hádaní mechaník.
- **Learning curve is a feature** – očakávame, že FU veterán potrebuje rádovo hodiny (5+) na pochopenie cenovej a vplyvovej mechaniky. Toto je success, nie failure. Onboarding nezjednodušujeme za cenu plochej hĺbky; tutorial môže byť stručný, ale samotné systémy ostávajú plne hlboké od začiatku.
- **SP-first, co-op compatible** – primárny dizajn je singleplayer. Co-op (2–8 hráčov, trust-based skupinka kamarátov) funguje s acceptable kompromismi: eventual consistency, ceny môžu byť 30 s zastarané voči ostatným klientom, frakčný state sa sync-uje lazy. NIE budujeme: dedikované servery, anti-cheat, PvP balansovanie, MMO architektúru.
- **No silent failures** – radšej crash s jasnou error message ("Pricing state for station X failed schema migration v3→v4") než tichý data corruption. Každý perzistent state súbor má schema version field. Pred risky migráciou robíme backup do `*.bak` súboru. Ak nevieme stav bezpečne prečítať, povieme to nahlas.

## Out of scope

- Žiadny 3D vesmírny combat – ostávame v 2D arénach kompatibilných so Starbound rendererom.
- Žiadne prepisovanie FU balance (ceny, recepty, damage hodnoty existujúcich itemov); meníme len to, čo FU nepokrýva.
- Žiadne multiplayer-only mechaniky; všetko musí fungovať v singleplayer (MP je bonus, nie requirement).
- Žiadny vlastný engine, fyzika, ani shaders – pracujeme výlučne v rámci toho, čo Starbound Lua API a JSON config systém ponúka.
- Žiadne procedurálne questy s textom generovaným AI alebo šablónami; emergent príbeh vzniká zo systémov, nie z quest generátora.
- Žiadna podpora pre vanilla Starbound bez FU – FU je tvrdá dependencia, nebudeme udržiavať dve verzie.
- Žiadne RTS-style flotily (mikromanažment 20+ lodí naraz); combat scope je jedna hráčova loď + sprievod max. niekoľkých AI lodí.
- Žiadne mikrotransakcie, externé služby, telemetria, ani sieťové volania mimo Starbound MP protokolu.
- Žiadne LLM-driven NPC dialógy – ani lokálne, ani cez API. Frakčné správy sú template-based, hráč nehovorí s jazykovým modelom.
- Žiadna ML / neural network AI v ľubovoľnej podobe – frakčná AI je rules-based + utility-based, nie naučená.
- Žiadny real-time adaptive alebo self-learning AI systém, ktorý mení váhy alebo pravidlá počas hry.
- Žiadne persistent MMO-style servery (24/7 uptime, hundreds of concurrent users); coop scope je max 2–8 kamarátov v session.
- Žiadne PvP-zamerané mechaniky a PvP balansovanie; ak sa dvaja hráči zabijú, je to ich problém, nie dizajnový.
- Žiadna Steam Workshop integrácia v aktuálnom scope (zváži sa v1.0+, nie teraz; do tej doby manuálna inštalácia/GitHub releases).
- Žiadne hard backward compatibility guarantees pre saves zo starších verzií modu; savy z v0.x nemusia byť kompatibilné s v0.y, varujeme v `KNOWN_ISSUES.md` a release notes.

## Target player experience

Mod cieli na štyri profily existujúcich Starbound/FU hráčov, v presne tomto poradí podľa priority pri dizajnových rozhodnutiach:

- **Primárny – FU veterán** (200+ h v FU): vyčerpal techtree, hľadá dôvod prečo navštevovať planéty inak než ako loot kontajnery. Toleruje a očakáva deep mechanics; learning curve v rádoch hodín je feature, nie bug. Referencia pre štýl hĺbky: Factorio/Stellaris (transparent depth) – nie Dwarf Fortress (opacitná hĺbka). Chce ekonomický a politický kontext nad existujúcim FU obsahom, ktorý dá zmysel ďalším 100 hodinám.
- **Sekundárny – Strategy fanúšik** (Stellaris/X4 hráč): chce sledovať mapu vplyvu, predpovedať konflikty, podporovať favorizovanú frakciu a vidieť dlhodobé následky svojich rozhodnutí. Frakčná AI musí byť pre neho čitateľná – vidí stav frakcie, jej motivácie a plánované akcie, aby mohol robiť informované rozhodnutia.
- **Terciárny – Trader/builder**: nepýta si viac bossov, chce profitovať z arbitrage medzi systémami, stavať trade posty a vidieť ako jeho rozhodnutia hýbu cenami v sektore. Pre neho je kľúčové, že každá cena má v UI viditeľný dôvod.
- **Paralelný – Co-op skupinka** (2–8 kamarátov zdieľajúcich galaxiu): trust-based prostredie, kde eventual consistency je akceptovateľná. Cena môže byť 30 s stará oproti druhému hráčovi, nikto v skupinke to nerieši. NIE sú to neznámi hráči na verejnom serveri.

Pocit, ktorý hra má vyvolávať naprieč všetkými profilmi: *"galaxia žije aj keď sa nepozerám"*. Hráč by mal mať pocit, že keď sa vráti po týždni, mapa vplyvu vyzerá inak, ceny sa pohli a vznikli nové príležitosti, ktoré nikto nenaskriptoval.

## Success criteria

Technické:
- Mod nezhorší TPS pod 55 v stabilnom systéme s 20+ navštívenými stanicami (merané v Starbound debug overlay).
- Žiadny update tick handler neprekročí 1 ms na entity (merané profilerom alebo `os.clock()` samplingom).
- Po vydaní novej FU verzie mod buď funguje bez zásahu, alebo si vyžaduje len patch v `mod/patches/` (žiadny rewrite core logiky).
- No silent data corruption v 10 h test session – mod radšej crashne s jasnou error message ako by mal tichom poškodiť save.
- Schema versioning prítomné v každom perzistent state súbore (ekonomické, frakčné, ship state) od prvého merged systému.
- P0 bug (save corruption, crash pri normálnej hre, freeze) má garantovanú response do 7 dní od reportu.

Behaviorálne / dizajnové:
- Hráč v priemernej 2-hodinovej session navštívi 3+ rôzne trade huby (merané v autorskom playtest, žiadna telemetria sa nezbiera).
- Cena minimálne jednej sledovanej komodity v testovanej galaxii sa za 5 herných dní pohne o ≥30 % bez priameho zásahu hráča.
- V testovacej galaxii nastane minimálne 1 dynamicky spustená vojna alebo zmena hraníc sféry vplyvu za 10 herných dní.
- Hráč dokáže vyhrať vesmírny súboj inou stratégiou než "viac DPS" (napr. boarding slabšej posádky, vyradenie štítového modulu) – overené playtestom.
- FU veterán hráč potrebuje 5+ hodín na pochopenie cenovej mechaniky. Toto je success kritérium, nie failure – znamená to, že systém má dostatočnú hĺbku.
- v0.1 release má funkčný rules-based frakčný systém, ktorý generuje aspoň 1 emergentnú vojnu za 10 herných dní bez hráčskeho zásahu.
- Každá dynamická cena má v UI viditeľný dôvod (napríklad `+30% blokáda Apexov`, `-15% prebytok titánia`); ceny bez dôvodu sa nepovažujú za hotové.

Dokumentačné:
- Každý vydaný systém má živý design doc v `docs/` so sekciami: ciele, mechaniky, dátové štruktúry, edge cases, otvorené otázky.
- Žiaden merged systém bez prechodu cez design doc fázu.
- `KNOWN_ISSUES.md` existuje v repo, verejne udržiavaný, aktualizovaný pri každom release.
- `docs/MODDING.md` existuje od v0.5 a popisuje stable JSON schémy pre tretie strany.
- Repo je verejne open-source od dňa 1 (žiadne private-first vývojárske obdobie).

## Faction AI roadmap (incremental hybrid)

Frakčná AI sa stavia inkrementálne, vždy s deterministickými a debugovateľnými pravidlami. V žiadnej fáze nie sú LLM, ML, neural networks ani real-time adaptive learning.

- **v0.1** – pure rules-based: jednoduchý quick & dirty rozhodovací strom (ak má frakcia X menej než Y zdrojov, znižuje agresiu). Cieľ: svet žije, aj keď AI je dummy.
- **v0.5** – pridáva utility AI vrstvu: každá akcia má skóre podľa kontextu (vlastný stav + susedia + ekonomika), frakcia vyberá najvyššie skórovanú akciu. Stále plne čitateľné v debug overlay.
- **v1.0** – pridáva personality modifiers per frakcia: archetypy ako *Aggressor*, *Trader*, *Isolationist*, *Opportunist*, *Defender*, ktoré škálujú váhy utility funkcií. Apex sa správa inak ako Floran, nie len kvôli sile.
- **v2.0+** – goals/agendas (frakcia sleduje dlhodobý cieľ cez viac herných dní) a inter-faction memory (frakcia si pamätá zradu z minulej vojny).

Pripomenutie: cieľom nie je "inteligentná" AI v ML zmysle, cieľom je predvídateľná AI s emergentným správaním. Hráč musí mať možnosť reverse-engineerovať frakčné rozhodnutia z viditeľných pravidiel.

## Modding philosophy (incremental platform)

Cieľ je byť platformou pre ďalšie mody – rovnaký vzťah, aký má FU voči vanilla Starboundu. Mod sám sa stáva ekosystémom, na ktorý sa dajú stavať ďalšie nadstavby.

- **v0.1** – data-driven JSON content (komodity, frakcie, ship moduly definované v JSON), repo verejne open-source na GitHube od prvého commitu.
- **v0.5** – `docs/MODDING.md` dokumentuje stable JSON schémy s príkladmi; v repo je referenčný example extension mod, ktorý ukazuje, ako pridať novú frakciu / komoditu / ship modul cez čistý JSON bez zásahu do core kódu.
- **v1.0** – public Lua hooks pre tretie strany (napr. `onPriceCalculated`, `onFactionDecision`, `onShipModuleInstalled`), naming conventions a hook signatúry zafixované a sémanticky versioned.

Disciplinárne pravidlá od dňa 1, aby cieľ v0.5/v1.0 bol vôbec dosiahnuteľný:
- Dáta v JSON, logika v Lua (žiadne hardkódované item listy v Lua súboroch).
- Schema versioning v každom perzistent súbore.
- Repo verejný, žiadne private branches s "tajnou" architektúrou.

Out of scope pre modding vrstvu (aspoň pre v0.x–v1.x):
- Steam Workshop integrácia (možno v1.0+).
- In-game mod manager / UI pre povolenie/vypnutie sub-modov.
- Hard backward compatibility guarantees medzi schémami; minor verzie môžu lámať JSON contract, ak je to opodstatnené, vždy s migráciou alebo varovaním v `KNOWN_ISSUES.md`.

## Bug classification (P0–P3)

- **P0** – save corruption, crash pri normálnej (nie edge-case) hre, mod uchne hru natoľko, že hráč musí force-killnúť proces. Response: do 7 dní (fix alebo aspoň workaround + warning v `KNOWN_ISSUES.md`).
- **P1** – feature nefunguje vôbec (napr. ceny sa nikdy nemenia), edge case crash pri špecifickej konfigurácii. Response: best effort, typicky 2–4 týždne.
- **P2** – misbehavior (ceny sa hýbu, ale logika je sporná), UI bugy, balance issues, suboptimálne číslo v utility funkcii. Response: ďalší minor release.
- **P3** – cosmetic (zlý sprite zarovnanie, typo v tooltipe), nice-to-have feature requesty. Response: keď je čas alebo PR z komunity.

## Version milestones

Tieto míľniky sa používajú naprieč dokumentom ako reference body pre incremental delivery (frakčná AI, modding philosophy, success criteria). Verzia je dosiahnutá až keď je splnené všetko v jej definícii.

- **v0.1** – funkčná Dynamic Pricing System + dummy rules-based frakčná AI (žiadny vesmírny combat zatiaľ). Cieľ: galaxia žije, ceny sa hýbu, frakcie majú jednoduché správanie.
- **v0.5** – utility AI vrstva pre frakcie + dokumentované JSON schémy + `docs/MODDING.md` + referenčný example extension mod v repo. Cieľ: tretia strana môže pridať frakciu/komoditu bez forku.
- **v1.0** – modulárny vesmírny combat (lode + boarding) + personality modifiers pre frakcie + public Lua hooks (`onPriceCalculated`, `onFactionDecision`, `onShipModuleInstalled`) pre tretie strany. Cieľ: feature-complete platforma.
- **v2.0+** – goals/agendas pre frakcie, inter-faction memory, prípadne Steam Workshop integrácia. Cieľ: dlhodobý emergent storytelling.

## Status

- **Verzia**: v3
- **Dátum**: 2026-05-24
- **Fáza projektu**: Pred-implementácia, prototypovanie storage vrstvy
- **Nasledujúci míľnik**: výsledky prototypu Q1/Q2 zapísané do `docs/economy-system.md`, potom storage layer DPS
- Tento dokument je živý – aktualizuje sa pri každej zmene scope alebo pillarov.
