# RUNEBOUND — Game Vision

Original third-person fantasy Action RPG for **co-op with 2–5 players on a
self-hosted server** (ROADMAP M09), fully playable alone except for the co-op
dungeons (3–5 players, extra content; the story is complete without them).
Godot 4.6, typed GDScript, PC, keyboard+mouse.

## The loop
MOVE → AIM → DODGE → ATTACK → IMPACT → LOOT → BUILD → REPEAT

## Pillars (priority order)
1. Game feel — every button press satisfying
2. Direct action combat: WASD + mouse aim, dodge positioning
3. Exceptional spell/impact VFX in a stylized 3D pixel-fantasy world
4. Exciting loot that changes how abilities behave
5. Character progression (levels + talent tree with 3 spec branches;
   abilities are learned, not handed out, and a hero takes **4 of about 12**
   class abilities into the field, CLASS_DESIGN "Three roles")
6. Several large, freely explorable zones that are open but dense, with
   sub-biomes, secrets and places that tell a story; repeatable endgame runs
   (later phases)
7. A small, dark, well-told story with dungeons, bosses and puzzles; it does
   not take itself too seriously in a few places, with rare, loving
   fourth-wall breaks about being written by an AI (STORY_DESIGN.md);
   three classes with real co-op roles

## Classes (user decisions 2026-09-29, built from M10)
Three roles, soft when alone (every class finishes the story solo), demanding
in the co-op dungeons:
- **Runebreaker, the tank:** armored rune warrior. Melee (Rune Cleave) builds
  **Resonance**, heavy rune abilities (Earthbreaker) spend it; taunt, block
  and threat hold enemies.
- **Elementalist (working name), the damage dealer:** ranged fire, lightning
  and frost; inherits Ember Lance, Chain Spark, Fracture Rune and Storm Step.
- **Root druid (working name), the healer:** plants breaking out of burnt
  earth; targeted heals, healing zones, shields and buffs.
Classes are data (`ClassData`) plus a hero script each. Since M10 phase 1
the Runebreaker and the Elementalist are separate classes; a save holds
several characters, each with its own world (CLASS_DESIGN "Three roles").

## Anti-goals
No MMO scope (co-op is 2–5 friends on one server, not a persistent world), no
derivative recreation of any specific ARPG's systems, no content before feel.
