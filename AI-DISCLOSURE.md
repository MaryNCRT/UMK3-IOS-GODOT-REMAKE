# AI Disclosure

This document exists because you have a right to know how the code in this
repository was produced, and because AI-assisted reverse engineering is
genuinely controversial in this community. We would rather be direct about it
than have you find out from a commit log.

The same disclosure applies to the
[decompilation repository](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp),
which is the other half of this project.

## The short version

**Most of this project was produced by Anthropic's Claude, working through
Claude Code, under human direction.**

That includes the binary analysis, the GDScript, the asset-format readers, the
fight engine, the tooling and the documentation you are reading now.

Claude appears in the commit history as a co-author, using the standard
`Co-Authored-By:` trailer. Commits are attributed honestly: if a change was
authored by an AI, the trailer says so.

## What was AI-generated and what was not

| Part | Who |
|---|---|
| Project direction, goals, scope | Human |
| Which engine, which character first, what to fix next | Human |
| Judging whether it *feels* like the game | Human, and this matters more than it sounds |
| Binary analysis and the measurements | AI |
| GDScript — readers, fight engine, UI | AI |
| Documentation | AI |

The human half is not a formality. Several of the most valuable findings in
this project started as a player saying "the low punch looks broken" or "the
fall is missing its end" — observations that turned out to point at real,
specific bugs in the animation streams that no amount of reading would have
prioritised on its own. The AI found the cause; the human knew there was one.

## Why this is disclosed

Reverse engineering communities care about provenance, and reasonably so. A
project that hides how it was made invites the question of whether its claims
can be trusted at all.

This project's answer is that **the claims are checkable**. Nearly every
constant in the fight code carries the address it came from. If a number is
wrong, the address tells you where to look, and you can disassemble that
function yourself and say so. That property does not depend on who or what
wrote the line.

Where a number is *not* measured, the comment says "chosen". That is the other
half of the same commitment: an AI is perfectly capable of producing a confident
paragraph about a number it invented, and the guard against that is labelling
every number with its provenance and keeping the labels honest.

## What this does not claim

It does not claim the code is correct because an AI wrote it, and it does not
claim the analysis is beyond question. It is a work in progress with a list of
open questions in [PROGRESS.md](docs/PROGRESS.md), several of which exist
because an earlier reading turned out to be wrong and was corrected. The
corrections are in the history too.
