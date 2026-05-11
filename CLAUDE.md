# Judgement Divided Handoff

This repo contains the Roblox game Judgement Divided. Treat it as an active, messy development workspace: do not revert unrelated changes, and do not assume Studio state matches the repo until Rojo is confirmed connected to this project.

## Project Layout

- `default.project.json` maps the Roblox DataModel for Rojo.
- `src/ReplicatedStorage/Shared` contains shared modules:
  - `Constants.lua`
  - `CharacterKits.lua`
  - `SkinCatalog.lua`
- `src/ServerScriptService` contains server combat, effects, hitboxes, and bootstrap logic.
- `src/StarterPlayer/StarterPlayerScripts` contains client combat input, HUD, camera, animation, lock-on, music, and menu scripts.
- `backend` contains the Discord bridge bot/API.

## Core Commands

Run from the repo root unless noted.

```powershell
& 'C:\Users\cashi\.cargo\bin\rojo.exe' build 'C:\Users\cashi\Downloads\Judgement Divided\default.project.json' --output "$env:TEMP\jd-rojo-check.rbxlx"; $code=$LASTEXITCODE; Remove-Item -Path "$env:TEMP\jd-rojo-check.rbxlx" -ErrorAction SilentlyContinue; exit $code
```

```powershell
& 'C:\Users\cashi\.cargo\bin\rojo.exe' serve 'C:\Users\cashi\Downloads\Judgement Divided\default.project.json'
```

```powershell
cd 'C:\Users\cashi\Downloads\Judgement Divided\backend'
node --check src/index.js
```

```powershell
& 'C:\Program Files\Git\cmd\git.exe' status --short --branch
```

## Studio / Rojo Notes

If Roblox Studio logs `Hello world, from server/client`, Studio is running the default template scripts or an unsynced place, not the real game.

If Studio logs infinite yields for:

```text
ReplicatedStorage.Shared:WaitForChild("Constants")
ReplicatedStorage.Shared:WaitForChild("CharacterKits")
```

then `ReplicatedStorage > Shared` is not populated correctly. The correct Rojo project should show `Shared > Constants`, `Shared > CharacterKits`, and `Shared > SkinCatalog`. A `Shared > Hello` module means Studio is connected to the wrong Rojo project.

The known correct local Rojo server recently served:

```text
Project: JudgementDivided
localhost:34872
```

Generated place files may exist at repo root:

- `JudgementDivided.rbxl`
- `JudgementDivided.rbxlx`

Do not commit generated `.rbxl` / `.rbxlx` files unless explicitly asked.

## Current Development Themes

Recent work focused on combat polish:

- Mobile knockdown/knockback should block dash, block, and jump inputs.
- Knockback should lock movement direction so players cannot steer during launch/slide.
- Combat readability was improved with damage feedback, camera impulses, and HUD cues.
- Sans animations were updated; current requested IDs:
  - Idle: `75493811600183`
  - Walk: `137021170208612`
- Sans music/theme IDs have changed several times; verify `BattleAudio.client.lua` before changing music again.
- Roland/Black Silence phase music has multi-phase behavior, including a phase 2 split track.
- Discord bot lives in `backend/src/index.js`; it supports slash commands, Roblox bridge jobs, and optional JD AI replies.

## Coding Style

- Lua code is Roblox Luau-style, mostly local functions and service modules.
- Prefer small defensive guards around character, humanoid, kit, and stat access.
- Avoid adding passive behavior that fights player state machines; check combat locks before accepting input.
- Use existing remotes under `ReplicatedStorage.Remotes`.
- Do not add destructive Git commands.

## Verification Checklist

After script changes:

1. Run the Rojo build command.
2. If backend changed, run `node --check src/index.js` inside `backend`.
3. Check `git diff --check`; CRLF warnings may appear and are usually existing line-ending noise.
4. In Studio, verify `ReplicatedStorage > Shared` contains `Constants`, `CharacterKits`, and `SkinCatalog` before pressing Play.

