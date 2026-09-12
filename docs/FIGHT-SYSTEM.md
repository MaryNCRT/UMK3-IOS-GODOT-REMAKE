# The fight system, as measured

[← README](../README.md) · [Architecture](ARCHITECTURE.md) · [Methodology](METHODOLOGY.md)

Everything on this page was read out of the retail armv7 binary. Addresses are
file offsets into `UMK3.armv7`; add `0x1000` for the vmaddr if you are working
from a section header.

---

## Input: ten bits

The fight receives one ten-bit word per player:

```
bit  0 UP   1 DOWN   2 LEFT   3 RIGHT   4 HP   5 LP   6 BL   7 HK   8 LK   9 RUN
```

The chain that proves it, end to end:

| Step | Function | Does |
|---|---|---|
| 1 | `TranslateJoybits` `0x00031a64` | packs both players' raw words into one, player two's bits eight places up |
| 2 | `swscan` `0x00055e90` | `changed = prev ^ now`; the down set and the up set go separately |
| 3 | `stack_switch_bits` `0x00055e2c` | each changed BIT becomes a row index into `_swtab`; a release adds `0x20` |
| 4 | `_swtab` `0x0016f10c` | 64 rows of `{button index, queue, player, flag}` |
| 5 | `QueueAndJump` `0x000572b8` | `table[button]` at `pl->0x60` — and it skips the table entirely for a release |

So the button tables are dispatched on the **press edge**. Reading `_swtab`
backwards gives the index each bit uses:

```
translated bit  4 -> 0 HP      bit 16 -> 1 LP
translated bit  5 -> 2 BL      bit  6 -> 3 HK
translated bit 17 -> 4 LK      bit 18 -> 5 RUN
translated bits 0..3 -> 6, 7, 8, 9, the four directions
```

And the four tables hold, in those slots:

| Table | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| `_bt_stance` `0x001655fc` | hi punch | lo punch | block | hi kick | lo kick | — |
| `_bt_duck` `0x001655d4` | uppercut | duck punch | duck block | duck kick h | duck kick l | — |
| `_bt_jump` `0x00165624` | jump punch | jump punch | — | jump kick | jump kick | — |
| `_bt_angle_jump` `0x001655ac` | flip punch | flip punch | — | flip kick | flip kick | — |

Run has no move: it is a modifier, not an attack.

---

## Strikes

`get_char_stk` `0x00055f88` → `_strike_tables` `0x00169fbc` → `_nj_strikes`
`0x00169f50`, which Scorpion shares with the other five ninjas — that sharing is
the check that it is the right table. 27 records, seven words each:

```
0 x      distance to the FAR edge, 16-bit signed
1 y      top, relative to the fighter's origin, 16-bit signed
2 w      width, measured BACK toward the fighter
3 h      height
4        (reaction << 8) | block-reaction index
5        (damage << 8) | chip damage
6 level  bit 1 set means it must be blocked LOW
```

`strike_check_regs` `0x00059280` turns those into a rectangle, and the
surprising half is word 0 against word 2:

```
facing right:  left = X + x - w
facing left:   left = X - x
right = left + w
top = Y + y ; bottom = top + h
```

The ninja set, decoded:

| strike | x | y | w | h | dmg | chip | lvl | reaction | block |
|---|---|---|---|---|---|---|---|---|---|
| hi kick | 96 | 4 | 65 | 44 | 24 | 5 | 1 | `t_r_hi_kick` | big |
| lo kick | 109 | 42 | 74 | 19 | 21 | 4 | 1 | `t_r_lo_kick` | big |
| hi punch | 77 | 1 | 53 | 33 | 11 | 3 | 1 | `t_r_hi_punch` | small |
| lo punch | 84 | 31 | 61 | 20 | 8 | 2 | 1 | `t_r_lo_punch` | small |
| sweep | 103 | 107 | 81 | 27 | 20 | 3 | **2** | `t_r_sweep` | small |
| duck punch | 77 | 54 | 54 | 18 | 6 | 2 | 1 | `t_r_duck_punch` | small |
| duck kick h | 72 | 59 | 65 | 30 | 12 | 3 | 1 | `t_r_duck_kickh` | big |
| duck kick l | 87 | 105 | 68 | 22 | 6 | 2 | 1 | `t_r_duck_kickl` | small |
| uppercut | 77 | −19 | 58 | 74 | 36 | 9 | 1 | `t_r_uppercut` | big |
| jump punch | 78 | 23 | 58 | 46 | 16 | 5 | 1 | `t_r_flip_punch` | big |
| jump kick | 78 | 2 | 66 | 59 | 19 | 6 | 1 | `t_r_flip_punch` | big |
| flip kick | 66 | 35 | 46 | 38 | 26 | 7 | 1 | `t_r_flip_kick` | big |
| roundhouse | 91 | 0 | 70 | 54 | 29 | 4 | 1 | `t_r_roundhouse` | big |
| knee | 74 | 33 | 49 | 52 | 18 | 3 | 1 | `t_r_elbow_knee` | big |
| elbow | 89 | 15 | 60 | 44 | 16 | 3 | 1 | `t_r_tusk_elbow` | big |
| spear | 0 | 0 | 22 | 22 | 8 | 2 | 1 | `t_r_scorpion_spear` | — |
| teleport | 76 | 17 | 54 | 42 | 15 | 4 | 1 | `t_r_scorp_tele` | — |

The uppercut's `y = −19` is the only record that starts above the fighter's own
origin, and the sweep is the only one with the low-attack bit.

### Two buttons, six attacks

The button does not name the move. The joy proc asks first:

- `t_knee_check` `0x0002f9d4` — a kick inside **74** units (`0x4a`) becomes a knee
- `t_elbow_check` `0x0002f8ac` — a high punch inside 74 becomes an elbow
- `is_stick_away` `0x00055df0` — the stick held back turns the high kick into a
  roundhouse and the low kick into a sweep

The choice is made **once**, when the button goes down, and the proc it jumps to
sets that attack's own animation and rate.

---

## Hits and blocking

`strike_check_regs`, after the boxes overlap:

```
disable_his_buttons
is_he_blocking(victim)
if blocking:
    chip = word5 & 0xff
    if chip < health[victim]:          <- one blt, and it is the whole rule
        reaction = _block_xfers[word4 & 0xff]
        apply chip
    else:
        fall through to full damage
else:
    damage = (word5 >> 8) & 0xff
    bar_reducer, add_combo_damage, react_xfer_him
```

**A block that would take you to zero does not hold.** The last hit of a round
always lands clean; nobody dies guarding.

`is_he_blocking` `0x0005837c` for a human player is a poll, in this order, with
no test of state or animation anywhere in it:

```
is_he_airborn        airborne is never blocking
part->0x30 & 4       set_no_block -- the spear's drag sets it
check_block_bit      the button must be DOWN at this instant
joy & 2              down as well: duck block, and it stops anything
level & 2            a LOW attack beats a standing block
otherwise            blocked
```

`check_block_bit` `0x0002eca8` masks the translated word with `0x20` for player
one and `0x2000` for player two — the same button either way.

The block itself: `t_joy_block` `0x000304d0` does `disable_all_buttons`,
`face_opponent`, then `t_do_block_hi` `0x0004cea0` — `stop_me_player`,
animation 12 at rate 3, tag `0x700`. Ducking is the same function with
animation 6 and tag `0x701`. Releasing runs `t_do_unblock_hi` `0x0004d7a0`,
which has no release clip at all: it plays the block clip's last two frames
*backwards*, four game frames each.

Blocked hits index `_block_xfers` `0x001671d8`, 24 procs, and the first thing
each does — or does not do — is call `rsnd_func`: index 5 is the big block
noise, 6 the small one, and eleven of the 24 make no sound of their own.

---

## Movement

| | measured | where |
|---|---|---|
| walk forward | speed and rate from `get_walk_info_f` | `plyrthread` state `0x42e` |
| walk back | `get_walk_info_b` | the branch at `0x00031352` |
| jump | vy −10.0, gravity 0.5 | `t_do_jump_up` `0x000581d0` |
| angled jump | horizontal 6.0 | `t_do_flip` |
| run | 8.0 **toward** the opponent, animation 70 at rate 3, voice 7 | `run_setup` `0x00030fbc` |
| turbo bar | 48 max, one per frame draining, 40-frame lockout, then one per frame back | `is_run_pressed` `0x0002f344`, `reduce_turbo_bar` `0x00030820`, `RaiseTurboBars` `0x00057a90` |
| walls | `G[0xb0] + 0x3a` and `G[0xb4] + 0x15f` | `gravity_n_bounds` |

The lockout is held *at* 40 for every frame you keep running, so the forty
frames count from when you stop, not from when the bar emptied. And the run
check only happens on the branch that took `get_walk_info_f` — running
backwards is not something the state machine can express.

---

## Reactions

`react_xfer_him` `0x000589d4` indexes `_reaction_table` `0x00166fc0` — 121
procs — with **byte 1** of word 4.

The uppercut is the one worked out end to end:

```
t_r_uppercut  0x00045348   blood 1, shake {6,6}, rsnd 10 (big smack)
  t_reaction_start 0x00044b84
    reaction_start_chores 0x00044b0c   face_opponent, stop_me_player
  t_rup3      0x00045ed4   THE LAUNCH
      pl->0x1c = 0x20000     2.0   away_x_vel
      pl->0x20 = 0xffee0000 -18.0  becomes the part's vy
      pl->0x24 = 0x5800      0.34375 becomes the part's gravity
      pl->0x28 = 5           the anirate
      pl->0x40 = 30          SCKNOCKDOWN
    t_flight  0x00054fb8  -> t_flight_call 0x00055aec  moves those into the part
  t_reaction_land 0x000425b8   on the way down
      shake_n_sound 0x000424fc    shake {6,6} and rsnd 13, the ground
      animation 30, find_ani_part2, rate 4, wait 3, then the getup
```

471 units of height against a fighter 130 tall: an uppercut in this game throws
you off the top of the screen, and that is correct.

The roundhouse flies too, with 6.0 away against a vy of −8.0 and the same
animation 30.

---

## What is not measured yet

- The blood particles' spread, speed and lifetime. The *count* and the spawn
  point are measured (`create_blood_proc` `0x0005877c`, `mk3_bloodevent`
  `0x00031d0c`); the motion is in `AddNewGameEvents`, which has not been read.
- The screen shake's amplitude curve. The trigger and the `{6, 6}` argument are
  measured; how it decays is chosen.
- Which frames of a move are *live* for the hit check. The engine calls
  `punch_strike_check` from each move's own state, and those states are not all
  decompiled; the port uses the middle half of the clip and says so.
- Where the HUD sits on screen. `DrawHUD` is 11.5 KB and unread; the sprites
  and the round tokens are measured, the layout is off a screenshot.
- The engine's own tick rate.
