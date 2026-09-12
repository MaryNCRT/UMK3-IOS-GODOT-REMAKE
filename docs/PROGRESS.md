# Progress

[← README](../README.md)

The percentages are honest estimates against a finished remake of the 2011 iOS
game, not against the arcade original. Where a number would be guesswork it says
so instead.

**Overall: roughly 20%.** One character of twenty-six is the number that
dominates everything else — but the character that exists runs on a fight
engine that is largely measured, and the second character is a data problem
rather than an engineering one.

---

## By area

| Area | State | Notes |
|---|---|---|
| **Asset formats** | 🟩 **95%** | `.meshset`, `.scene`, `.events`, `.bones`, `.skin`, `.skinanim`, `.lighting`, PVRTC, the frame lists. `.meshset` validated against 604 of 605 files |
| **Input contract** | 🟩 **100%** | Ten bits and four button tables, verified end to end through `_swtab` |
| **Strike data** | 🟩 **100%** | All 27 records: boxes, damage, chip, level, reaction, block reaction |
| **Hit detection** | 🟩 **90%** | `strike_check_regs` and `is_he_blocking` transcribed. Which frames are *live* is still chosen |
| **Block** | 🟩 **95%** | Standing, ducking, chip, the no-block flag, the sounds. The block judder's exact frames are a reading |
| **Run** | 🟩 **95%** | Speed, animation, rate, voice, and the whole turbo bar |
| **Movement** | 🟨 **70%** | Walk, jump, angled jump, duck, walls, floor. Turning is the obvious rule, not `t_walk_flip_check` |
| **Attacks** | 🟨 **75%** | 16 strikes with their own animation, rate, retraction and sound. The combo system is untouched |
| **Reactions** | 🟨 **40%** | 6 of the 121 `t_r_*` procs read in full. The uppercut end to end; the rest use their measured knockback and a shared fall |
| **Specials** | 🟨 **35%** | 3 of Scorpion's. The detector is this project's own — `seq_lookup` is not decompiled |
| **Animation** | 🟩 **90%** | 82 streams decoded with both parts, per-move rates measured |
| **Sound** | 🟨 **70%** | 16 `rsnd` tables and the voice groups mapped; `MKEvent_Add` subtype 3 still unread |
| **HUD** | 🟨 **60%** | Real sprites, real round tokens, the run meter. `DrawHUD`'s layout is off a screenshot |
| **Stages** | 🟨 **61%** | 11 of 18 arenas load, light and run their own effects |
| **Roster** | 🟥 **4%** | Scorpion. The pipeline that imported him is general |
| **Match flow** | 🟥 **10%** | Rounds and a winner. No intro, no "FINISH HIM", no continue |
| **AI** | 🟥 **0%** | Two human players only |
| **Fatalities** | 🟥 **0%** | Meshes and textures located, logic not decompiled |
| **Front end** | 🟥 **15%** | Title, a menu and a stage picker. No character select |
| **Shell** (this project's own) | 🟩 **90%** | Pause, key config, video options, gamepad support, saving |

---

## What was measured most recently

Newest first. Each of these replaced something that had been chosen or was
simply wrong.

- **Attack retraction.** Every attack stream has a second part and it was being
  cut off. The low punch ended with the arm extended and snapped back.
- **Per-move animation rates.** All 16, plus two per-character byte tables.
  Kicks were running six times too slow.
- **The uppercut's launch.** −18.0 against a gravity of 0.34375, not −12.0
  against 0.375. The arc was 64 frames instead of 104.
- **The landing.** `t_reaction_land` plays part two of the knockdown at rate 4;
  the fall had no ending.
- **The block, entirely.** It had never worked: started on a press edge when
  the engine polls a level.
- **Chip damage and block reactions.** A whole half of the strike records that
  had not been read.
- **The run**, which did not exist at all.
- **The round tokens.** `DrawHUD` uses `_CoinTPage`, the gold dragon coin, not
  the invented squares that were there.

---

## What is chosen, and would change if read

Grep for the word "chosen" in `umk3/`. The ones that matter:

| Thing | Would be settled by |
|---|---|
| Blood particle motion | `AddNewGameEvents` `0x000732a8` |
| Screen shake decay | the same |
| Per-character voice indices | the same — `MKEvent_Add` subtype 3 |
| HUD placement | `DrawHUD` `0x000282dc` |
| Which frames a strike is live for | each move's own state proc |
| Special-move detection | `seq_lookup` in `playback.c` |
| The engine's tick rate | not yet located |

---

## The obvious next steps

1. **A second character.** The import pipeline is general; what is character-
   specific is the strike table pointer, the animation table and the voice set.
   This is the highest-value work by a distance.
2. **`AddNewGameEvents`** — 6.5 KB that turns three chosen things into measured
   ones at once.
3. **The remaining reaction procs.** 6 of 121 read; each is small.
4. **The seven missing arenas.**
5. **An AI opponent**, which the binary has and nobody has looked at.
