# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.0] - 2026-04-29 — Factorio 2.0 Port

### Added
- Hero banner image generated via Codex (gpt-image-2), industrial railway night scene.
  Files: hero.png
- In-game screenshots showing dense intersection and roundabout signal placement.
  Files: screenshot/Screenshot1.png, screenshot/Screenshot2.png
- README.md with hero image, screenshots, feature overview, 2.0 rail type table, and installation instructions.
  Files: README.md
- Pre-registered collision layers as `CollisionLayerPrototype` via `data:extend` (required by Factorio 2.0); registers `rail_signal_layer_1–8` using underscore naming per docs.
  Files: data-final-fixes.lua
- `safe_get_mask` pcall wrapper to handle entity types absent from `collision-mask-defaults` without crashing.
  Files: data-final-fixes.lua
- Dynamic rail type detection via name pattern (`contains "rail", not "signal"`) covering all Factorio 2.0 rail types.
  Files: data-final-fixes.lua
- `NON_RAIL_ENTITY_TYPES` exclusion set for `rail-planner` (ItemPrototype), `rail-remnants` (CorpsePrototype), and `rail-support` to prevent false positives.
  Files: data-final-fixes.lua
- Per-entity backup/restore for all detected rail types, replacing the old `straight-rail`/`curved-rail`-only copy.
  Files: data-final-fixes.lua
- Published to Factorio Mod Portal as `Space-Efficient-Rail-Signals-2` with fork/port attribution.
  Files: info.json

### Changed
- Ported mod target from Factorio 1.1 to 2.0; bumped `factorio_version` and `version` to `1.1.0`.
  Files: info.json
- `collision-mask-util` still required (it ships in 2.0), but `add_layer`/`remove_layer`/`mask_contains_layer` replaced with direct `mask.layers[name] = true/nil` operations per updated 2.0 API.
  Files: data-final-fixes.lua
- `cmu.get_mask` no longer mutates entities in 2.0; code now explicitly assigns `collision_mask` back before modification.
  Files: data-final-fixes.lua
- Mod internal name changed to `Space-Efficient-Rail-Signals-2` and title updated to note Factorio 2.0 Port.
  Files: info.json

### Fixed
- Crash `Unknown entity type: rail-planner` caused by `rail-planner` (an ItemPrototype) being incorrectly detected as a rail entity type.
  Files: data-final-fixes.lua
- Variable scoping bug in `edit_non_rail_segment` where `new_layer` was not declared local.
  Files: data-final-fixes.lua
- `prototypes_collide` parameter name shadowing; added self-comparison guard.
  Files: data-final-fixes.lua
- `curved-rail` no longer exists in Factorio 2.0 — detection now covers `curved-rail-a`, `curved-rail-b`, `half-diagonal-rail`, `elevated-*`, and `legacy-*` variants.
  Files: data-final-fixes.lua
