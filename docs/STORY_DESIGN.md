# RUNEBOUND — Story Design

Direction only: user decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien").
The first lore texts arrive with M12 (the Highlands with substance), the
dialogue and quest system with M14 (Story & RPG). Lines marked
**proposal** are the implementer's suggestions, not the user's decisions.

## The story stays dark
The story is serious and dark, like the look and the music: the Shattered
Rune, the Vessel, the ash over the Highlands. The arc runs around the
Shattered Rune through the hub and the zones (ROADMAP M14). Sigrun Runewright
gets the first story.

## The meta layer: seasoning
The user wants the game not to take itself too seriously, and to be open
about being made by an AI. The decisions:
- **Dose: seasoning.** The breaks are rare so that they land. Most lines of
  any character stay serious and in the world.
- **Directness: explicit.** Characters know that an AI wrote them and say
  so. The game needs no in-world allegory for it.
- **Tone: self-ironic and loving.** The game laughs at itself but likes its
  world. It is not cynical satire and not slapstick.
- **Carriers:** NPC dialogues; items and quests (item descriptions, legendary
  texts, quest titles, journal entries); lore objects and secrets (graves,
  notes, ghosts, hidden places).
- **Not carriers (not chosen):** UI, loading tips, death texts, boss intros,
  credits.

Proposals:
- No break in the middle of a boss fight or a moment meant to be dark. The
  break can come afterwards.
- A joke should be true where it can be. Sigrun's lines really are marked as
  placeholders in `scripts/world/trainer_npc.gd`, and every raider camp
  really has exactly two log seats.
- Never real people, the players' names, the home network or anything
  private (the repo is public). Nothing that mocks the players.

## Tone reference
The user saw these lines when choosing the tone. They set the level, and
they are not final text.

Loving self-irony (the chosen tone):
- DE: „Ich weiß, meine Zeilen sind Platzhalter. Aber ich übe schon für die
  richtige Geschichte, versprochen.“
  EN: "I know my lines are placeholders. But I'm already practising for the
  real story, I promise."
- DE: „Die Highlands sind etwas … braun. Wir arbeiten dran. Der Himmel ist
  aber schön, oder?“
  EN: "The Highlands are a bit... brown. We're working on it. The sky is
  nice though, isn't it?"

Explicit (the chosen directness):
- Sigrun, DE: „Ich wurde von einer KI geschrieben. Die meisten meiner Sätze
  enthalten das Wort Rune. Das ist kein Zufall. Das ist ein Muster.“
  EN: "I was written by an AI. Most of my sentences contain the word rune.
  That's not a coincidence. That's a pattern."
- A sealed gate, DE: „Als großes Sprachmodell kann ich dieses Tor leider
  nicht öffnen.“
  EN: "As a large language model, I'm afraid I can't open this gate."

Ideas, not decided: the tell-tale words of AI text ("a testament to", "a
rich tapestry", "delve") as a rare running gag in item texts; a "kill ten"
quest whose journal notices that ten is simply the number one picks; a hidden
NPC in a cave who was never in the plan.

## Dialogue
- **Answer options, mostly flavour:** a choice changes a reaction, a small
  reward or an extra line. There are no large consequences and no branching
  endings.
- Proposal for co-op: every player talks to NPCs on their own machine, as
  with the trainer today. Results that change the world (quest flags) go
  through the server like every other world flag.

## Languages
- **German and English, with a language switch in the menu.** Every
  player-facing text is a key in a translation table. Whether that is
  Godot's TranslationServer with CSV or PO files is decided in M12.
- Both languages are written, never machine-translated. A joke is rewritten
  for each language when a pun does not carry over.
- From M12 on (the first lore texts) every new text is bilingual. The
  existing UI follows in M14.
