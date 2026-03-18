Test focus: menu flow, character select, combat, dummies, duels, training server, and lock-on.

How to play:
1. Open the loading screen, then main menu.
2. Press `Play`.
3. Pick `Sans` or `Magnus`. Slots 3-5 are not available yet.
4. Use the top-right button to swap between `Main Game` and `Training`.

Controls:
`Mouse1` M1
`LeftShift` dash
`F` block
`Q/E` swap Sans modes
`1-5` abilities
`MMB` lock on
`X` relock last target

What to test:
- Death/reset should return you to the main menu.
- Characters should only be selectable from the menu.
- Sans: no M1, mana regen, idle/walk animations, mode swap on `Q/E`, counter lasts longer.
- Magnus: M1 combo and all 5 abilities should hit correctly.
- Block has cooldown, pulsing aura, and should fade out on release.
- Cooldowns should only apply to the exact move used, not the same slot in other Sans modes.
- Lock-on should center the target, shift camera right, and keep your body facing the target.

Dummies:
- `Target Dummy` normal
- `Blocking Dummy` blocks/reduces damage
- `Attacking Dummy` attacks and shows hitbox if enabled
- All dummies should respawn and show name + HP bar

Duels:
- `/1v1 player` should send a request
- `Y/N` or `/accept` `/decline` should work
- `/1v1 dummy` should send you to the duel arena

Training server:
- Players should not damage each other
- Dummies should still take damage

Report bugs with: character, move, target, server (`main` or `training`), lock-on on/off, expected result, actual result.
