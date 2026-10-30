# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.3.0] - 2026-10-30

### Changed
- The board and controls use the shared layout: a full-width action bar, the
  scale filling the room it leaves, and a status line that wraps in landscape
  instead of being cut off.
- The difficulty entry in the title-bar menu reads "Difficulty: Easy".
- Once the game is won or lost, the action bar shows "New game" in place of
  Weigh / Clear Pans / Guess.

### Fixed
- The difficulty names (in the menu and in the "Easy (6 balls, 2 weighings)"
  picker) were always English: they are now translated.

## [1.2.0] - 2026-10-29

### Changed
- Redesigned play screen. The scale is drawn properly (fulcrum, hanging
  pans, a beam that tilts towards the heavier side) and the balls are round,
  numbered and tapped directly, on the scale or in the "Off the scale" tray
  below it, instead of through a row of tiny `L:3`/`R:5` buttons. A ball on
  a pan leaves a faint outline in its tray slot, so slots never move.
- The beam only stays tilted while the pans hold exactly what was weighed;
  moving a ball levels it, so it never shows a result for an unweighed set-up.
- The weighing log is a table with one row per allowed weighing (unused rows
  greyed) and a small tilted-scale pictogram per result, instead of one long
  line that ran off the screen after two weighings.
- Once the game ends, the odd ball is shown filled in black.

### Fixed
- The log showed `[1,2,3] < [4,5,6]` when the *left* pan was heavier.


## [1.1.14] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.1.13] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.12] - 2026-08-05

### Added
- Add ES and DE translations

### Changed
- Add issue/PR templates and CONTRIBUTING.md

## [1.1.11] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

## [1.1.9] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.1.6] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE

## [1.1.3] - 2026-07-21

### Added
- Own translations locally instead of via game-common

## [1.1.1] - 2026-07-15

### Added
- Adopt TitleBar header, sync common/ with game-common

### Changed
- Remove ../game-common/ fallback from package.path

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0

## [1.0.1] - 2026-07-07

### Changed
- Remove redundant variable alignment in buildLayout
