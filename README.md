# EasyRaidForever

Loot-Addon der Gilde **[skill issue]** für WoW Forever. Arbeitet mit der Gildenseite https://skill-issue-de.pages.dev zusammen
(Repo: https://github.com/amptie/skill-issue-page) – die Seite ist die Datenquelle, das Addon macht nur das, was ingame passieren muss.

## Funktionen

- **Import von der Seite**: Raid bearbeiten → Loot → „Für Addon exportieren“, ingame `/erf import` → einfügen.
  Enthält Anmeldungen, Reservierungen (SR/SR+ mit Bonus), Main/Dual Spec und die Items der Instanz. Wer importiert, ist Loot-Master.
- **Würfeln**: reservierte Items nur unter den Reservierern (SR, + SR+-Bonus), sonst Main Spec > Dual Spec > Off Spec > Gier.
  Ehrliches `/roll` – das Addon liest die Würfelzeilen aus dem Chat.
- **Loot-Master-Fenster** (`/erf lm`): Items aus Leichen/Taschen, einzeln oder alle auf einmal auswürfeln (auch mit langem Timer),
  vergeben per Plündermeister oder Handel (Handels-Hilfe legt das Item automatisch ins Fenster).
- **Export für die Seite**: `/erf export` → auf der Seite unter Raid bearbeiten → Loot → „Addon-Export einfügen“.

## Befehle

`/erf` Fenster · `/erf import` / `/erf export` · `/erf lm` Loot-Master · `/erf rolls` / `/erf results` ·
`/erf item <Link>` Item auf die Liste · `/erf check` prüft, was der Client unterstützt · `/erf debug` · `/erf reset confirm`

## Aufbau

- `Core/` – Hilfen, Datenbank (SavedVariables `EasyRaidForeverDB`), Serializer, Addon-Nachrichten
- `Raid/` – importierter Raid, Loot-Liste, Würfel-Logik, Austausch mit der Seite (`Transfer.lua`)
- `UI/` – Fenster; `Locales/` – Englisch (Quelltexte) + Deutsch
- `Libs/` – LibStub, LibDeflate, CallbackHandler, LibDataBroker, LibDBIcon

Das Textformat (`SIR1:` Seite → Addon, `SIL1:` Addon → Seite) muss byte-gleich zu `lib/addon.js` der Gildenseite bleiben.
