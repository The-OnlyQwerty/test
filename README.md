# Judgement Divided

Starter Roblox battlegrounds project inspired by anime arena fighters such as Alternate Battlegrounds.

This is not a clone of any specific game. It gives you a clean foundation for:

- server-authoritative melee combat
- multiple character kits
- M1 combo chains
- blocking
- dashing
- cooldown-based special moves
- simple resource bars
- mode-switching for stance characters
- easy character kit expansion

## Project layout

- `src/ReplicatedStorage/Shared`: shared config and fighter kits
- `src/ServerScriptService`: combat service and server bootstrap
- `src/StarterPlayer/StarterPlayerScripts`: client input and simple effects hooks
- `backend`: Discord bot + HTTP bridge starter

## Controls

- `MouseButton1`: M1 combo
- `Q`: dash
- `F`: hold block
- `R`: switch mode
- `T`: swap between Sans and Magnus during testing
- `Z`, `X`, `C`, `V`, `G`: abilities 1-5

If Sans is in Telekinesis mode, `W`, `A`, `S`, `D`, and `Space` also send target movement commands after a grip lands.

There is now a basic in-game HUD with:

- character selection buttons for Sans and Magnus
- a mode switch button for stance characters
- HP, mana, and stamina bars
- live ability labels and cooldown overlays
- a separate main menu with Play, Credits, Skins, and Settings pages
- admin-only client-side hitbox debug rendering with `H`

## Studio setup

1. Install [Rojo](https://rojo.space/) if you want file sync.
2. Open this folder in your editor.
3. Run `rojo serve`.
4. Open Roblox Studio and connect with the Rojo plugin.
5. Create a basic arena with spawn points.
6. Press Play with 2+ test clients to validate combat.

If you do not want Rojo, you can still copy the scripts into Studio manually using the same folder structure.

## Discord bridge

A starter Discord-to-Roblox admin bridge is included in `backend/`.

- Discord slash commands queue jobs
- Roblox servers poll and execute whitelisted actions
- current actions: `announce`, `setkills`, `buff`

Setup instructions are in `DISCORD_BRIDGE_SETUP.md`.

## Current characters

### Sans

- no M1 combo
- block becomes a Bone Wall
- passive Karmic Retribution applies damage over time on hit
- mana is used for dodging and abilities, and also drops when Sans gets hit
- modes:
  - `Bones`: ranged bone attacks, bone zone, counter
  - `Telekinesis`: grip a target, then reposition them with `WASD` or `Space`
  - `Blasters`: build up gaster blasters, then track/fire them

### Magnus

- 4-hit M1 combo with sword on the later hits
- close-range sword and dagger specials
- launcher
- delayed ultimate sword rain

## How kits work

Each fighter kit lives in `src/ReplicatedStorage/Shared/CharacterKits.lua`.

Every ability entry can define:

- `Cooldown`
- `Damage`
- `Range`
- `Knockback`
- `Stun`
- `ManaCost`
- `StaminaCost`

The current prototype ships with `Sans` and `Magnus`.

## Good next steps

- add VFX and animation ids
- add ragdoll or launcher states
- add a real character select UI
- add ranked or casual match flow
- add a proper hitbox system using box casts or custom parts
- add UI for cooldowns, character select, and damage numbers
- replace placeholder combat effects with animations, VFX, and sound

## Design guidance

Games in this genre live or die on responsiveness and readable state changes. Keep these rules:

- input should feel immediate on the client
- damage and hit validation should stay on the server
- stuns, i-frames, and cooldowns need one clear source of truth
- every move should communicate startup, active time, and recovery

This starter keeps those boundaries simple so you can expand without rewriting the whole combat layer.
