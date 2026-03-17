Test build focus: menu flow, combat, dummies, lock-on, camera, resources, and Sans animations.

How to play:
1. Open the main menu.
2. Press Play.
3. Pick `Sans` or `Magnus` in character select. Slots 3-5 should say they are unavailable.

Controls:
`Mouse1` M1
`LeftShift` dash
`F` block
`Q/E` swap Sans modes
`1-5` abilities
`MMB` lock on
`X` relock last target
`H` hitbox debug if admin / Studio

What to test:
- Dying or resetting should send you back to the main menu.
- You should only be able to change characters from the menu.
- Sans has no M1, uses mana, regens mana, and now has idle/walk animations.
- Magnus M1 should visibly hit and deal damage.
- Stamina should regen and only be spent on dash.
- Lock-on should work on players and dummies.
- While locked on: camera FOV changes, target stays centered, camera shifts right, and your body faces the target.
- Unlocking should restore normal camera/body behavior.

Dummies:
- `Target Dummy`: normal damage
- `Blocking Dummy`: reduced damage
- `Attacking Dummy`: attacks with a visible debug hitbox if hitboxes are enabled
- All 3 should have names and HP bars above their heads

Credits should show:
`The_OnlyQwerty: Owner`
`Cavespider07: Animator`
`Friday1234g: Map Builder`

When reporting bugs, include: character used, target used, move/input, whether lock-on was active, whether hitbox debug was on, expected result, and actual result.
