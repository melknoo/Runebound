# RUNEBOUND — Story Design

Direction: user decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien").
The campaign "The Runebound" below: user decisions of 2026-10-20 (concept,
structure, co-op rules); the beat sheets, names and sample lines are the
implementer's draft for the user's review. The first lore texts arrived with
M12, the dialogue and quest system comes with M14a. Lines marked
**proposal** are the implementer's suggestions, not the user's decisions.

## The story stays dark
The story is serious and dark, like the look and the music: the Shattered
Rune, the Vessel, the ash over the Highlands. The arc runs around the
Shattered Rune through the hub and the zones (ROADMAP M14). Sigrun Runewright
gets the first story.

## The campaign: "The Runebound" (decided 2026-10-20)
The user chose concept A of three ("Die Runengebundenen"; the others were a
cult that sang the Rune apart, and a frost that the Rune kept out). Shape:
classic, a linear prologue, a guided first act, then an open world.

**Decided by the user:**
- **Scope:** the existing world plus two new zones, about 5-7 hours of main
  story.
- **Prologue:** its own small zone, linear, 25-35 minutes, level 1 to 2, ends
  in Runehold.
- **Presentation:** a dialogue window (speaker name, portrait, answer options
  that are mostly flavour) and short camera pans with letterbox bars,
  skippable. No voice.
- **Story NPCs:** allowed at story places (a companion in the prologue, a
  quest giver at a ruin), plus Runehold and one safe outpost per new zone.
  This refines "no outdoor NPCs", which was about ambient world life.
- **Levels:** fixed per region, with a recommended level on the map and the
  gate.
- **Act 1 gate:** for new characters the Cistern and the Warrens stay sealed
  until Act 1 ends; existing characters keep everything open.
- **New characters** play the prologue; from the second character on they may
  skip it at creation. Existing characters start in Act 1 (Sigrun calls them).
- **Co-op:** every hero present gets a quest step (like XP); every player
  talks to NPCs on their own machine; a story boss the server has already
  killed comes back online while a present hero still needs it.

### Premise
The Rune was a binding. The Runewrights of Runehold forged it long ago and
tied the wild powers of the land to it: the fire that Emberfall carried over
the Highlands, the deep water under the Cistern, the storm the Circle drew
down at the Stormwatch, and the old winter that slept in the southern valleys.
While the Rune held, the dead of the Highlands rested too.

Nobody asked the bound powers whether they agreed (the Stormwatch entry says
so already). Brother Aldric, a keeper of the Cistern and Sigrun's old teacher,
came to believe the binding was a cruelty. He cracked the Rune's four anchors
from within and, on the night of the Breaking, took its heart out of the
socket in the Spire. The Rune shattered. Emberfall fell, and its fire sank
into the Charwood and the deep kilns. The Cistern's water turned. The storm
began to wear its caller. The frost crept down into the valleys. The dead of
Ashwick got up. Ash has fallen ever since, and shards of the Rune came down
with it.

Some shards struck living people. The heroes are such people: refugees from
Ashwick who were hit by a falling shard on the night they fled. The shard in
them lets them learn runes (the in-world reason for abilities, tomes and the
return at a shrine). They are **Runebound**.

### Timeline
1. The Rune holds for centuries; the Runehold compact (keepers, smiths, the
   Circle, the Runewrights) lives around it.
2. Aldric cracks the anchors. The Cistern sings at night, the kilns light
   themselves, the Stormwatch's blades turn without wind (existing lore).
3. The Breaking: the heart is gone, the ash starts to fall (Tobin's name
   day). Emberfall falls on the ridge.
4. Nine days later the dead walk in Ashwick. The bell never rings (the priest
   cut the rope). The last villagers flee down the old road to Runehold:
   **the prologue**.
5. The game's present begins on the morning the refugees reach Runehold.

### Cast
| Who | Where | Role |
|---|---|---|
| **Edda** | prologue, then Runehold by the hearth | leads the refugees; the soldier's widow (the letter "Edda, the ash has not stopped falling ..."). Steady, dry, tired. |
| **Sigrun Runewright** | Runehold | the last Runewright, Runebreaker trainer, the mentor. Missed the night of the Breaking. Aldric taught her her first rune. Gets the first personal story. |
| **Maren Emberwright** | Runehold | Elementalist trainer; her family were the Warrens' smiths (her thread is the fire, Act 2). |
| **Hild Ashroot** | Runehold | Druid trainer; listens to the Charwood's roots (fire thread, Act 2; side quest in Act 1). |
| **Ylva Ashbrew** | Runehold | potions and food; sharp tongue, the most frequent carrier of a rare meta line. |
| **Tova Stormward** | Runehold | storm trader, of the Circle's wardens (the optional storm thread). |
| **The priest of Ashwick** | Highlands (ghost) | already in the game; in Act 1 he remembers the grey brother. |
| **The Reeve of Ashwick** | prologue boss | kept the village's ledger and its toll gate; holds the gate in death: nobody leaves without paying. |
| **Brother Aldric** | only traces in Act 1 | a keeper's knot, a seal, a voice in a shard. Met in Act 3. |
| **Bram** | a ruin in the Highlands (story place) | a raider who deserted; gives the "kill ten" side quest. |

### Structure
| Part | Where | Level | Time | Built in |
|---|---|---|---|---|
| Prologue "The Ash Road" | new zone `ash_road` | 1-2 | 25-35 min | M14a |
| Act 1 "What the Shards Sing" (guided) | Runehold, Highlands, Colossus, Spire | 2-5 | ~1.5 h | M14a |
| Act 2 "Four Anchors" (open, any order) | Cistern (4), Warrens (5), new zone **Frostvales** (6-9); Stormwatch optional (co-op) | 4-9 | ~2.5 h | M14b, M15a |
| Act 3 "The Breach" | new zone **The Breach** (9-13), final dungeon | 9-13 | ~1.5 h | M15b |

### Prologue: "The Ash Road" (M14a)
A night road from the edge of Ashwick down to Runehold: one S-shaped road,
ridges for walls, a gorge with a bridge, the toll gate at the end. Ash falls
the whole time. Level 1 enemies; the zone ends with the hero at level 2.

| Step | Place | What happens | Teaches |
|---|---|---|---|
| P1 The last camp | spawn, a cart, two refugees | Edda wakes the hero: "They're coming up from the graveyard." | move, camera, [E] talk |
| P2 The dead come | the road behind the camp | three grave shamblers; Edda gets the children onto the cart | basic attack, dodge |
| P3 The shard | a clearing | camera pan: a shard falls burning out of the sky and strikes the hero. Edda: "Your hand. It's glowing." | the first ability slot |
| P4 Ambush | the road bend | raiders hit the cart; a chest afterwards holds a healing draught | inventory (I), drink with right-click |
| P5 The bridge | the gorge | the old bridge holds for the hero and breaks behind them (camera pan); no way back | - |
| P6 The toll gate | the arena | **the risen Reeve** (boss): mace slam, a toll-ring wave, raises the dead at 66 % and 33 %, lunges at kiters | reading telegraphs |
| P7 Runehold | the north gate | camera pan on arrival: Sigrun sees the glow in the hero's hand; a short dialogue; act card "ACT I" | - |

- **XP budget:** about 250 in total (level 2 needs 80, level 3 needs 323): no
  discovery XP in the prologue, low kill values, the Reeve about 100.
- **Death:** back at the last step's spot.
- **Edda** waits at each step (no escort AI) and then stands by the Runehold
  hearth.
- **Skip** (from the second character on): straight to Runehold at Act 1 with
  the prologue's XP and rewards.

### Act 1: "What the Shards Sing" (M14a)
Guided by quests; the Highlands are open, the Cistern and the Warrens stay
sealed for new characters until the act ends.

1. **Runebound** (`a1_call`): Sigrun looks at the hero's hand and names it.
   She sends the hero to their own trainer (a Runebreaker stays with her).
2. **What the shards sing** (`a1_shards`): bring three rune shards from the
   southern Highlands. Sigrun listens to them: one hums towards the north,
   one is heavier near graves, one carries half a voice.
3. **The bell of Ashwick** (`a1_ashwick`): go to Ashwick and hear the
   priest's ghost (breaking the lanterns is optional, because online the
   graveyard may already be cleansed). By the graves lies a grey cord tied in
   the keepers' knot. Sigrun recognises the knot and does not want to.
4. **The warden in the north** (`a1_colossus`): the Ashvein Colossus guards
   the way to the Spire.
5. **The empty socket** (`a1_spire`): defeat the Vessel, then look at the
   socket. Camera pan: the socket is empty, and its edges are clean. The Rune
   did not break; it was opened. In the socket lies a keeper's seal. Back to
   Sigrun: "Aldric. He taught me my first rune." Act card "END OF ACT I".
   The Cistern and the Warrens unseal.

Migrated characters (Colossus or Vessel already dead) run through the chain
quickly: retroactive steps count at once, but the socket scene still plays.

**Side quests in Act 1** (proposal):
- **The last letter** (Edda): find the soldier's letter on the Ashford
  slopes (existing lore) and bring it to Edda. Answer: tell her how it
  really reads, or that he died well (flavour). Reward: his ring.
- **A name for the nameless** (the nameless grave in Ashwick, existing
  meta lore): the grave asks for a name; three answers (DE "Bernd", "Rune",
  "Gerald"; EN "Bob", "Rune", "Gerald"). The stone keeps the chosen one.
  Rune gets the reply "Of course."
- **Ten is a good number** (Bram at a ruin): kill ten raiders. The journal
  notices that ten is simply the number one picks.
- **The Charwood breathes** (Hild): check the warm roots behind the hunter's
  note, put out the wisps; the first hint of the fire thread.

### Act 2 and Act 3 (outline, not built)
- **Water** (Cistern): Aldric's cell among the keepers; the Deepmaw swallowed
  the water anchor.
- **Fire** (Warrens and the Charwood): Maren's family forge; the Broodmother
  broods on the fire anchor.
- **Frost** (new zone **Frostvales**, levels 6-9): with Emberfall dead the
  old winter came down; an outpost of the compact holds a pass; a frozen
  dungeon holds the frost anchor.
- **Storm** (optional, co-op): the Stormwatch and Tova; the storm anchor makes
  the finale easier and adds a line to the ending. The story is complete
  without it.
- **Act 3, The Breach** (levels 9-13): from the anchors Sigrun forges a
  counter-rune that opens the Runewrights' first forge in a crater in the far
  north. Aldric's followers, the Unbound, hold it. In the forge Aldric wants
  to break the heart for good: "Everything bound wants to be free." The heart
  will not hold in stone any more, only in the living: the Rune is reforged
  inside the Runebound, who carry it together. The ash stops falling (the
  epilogue in Runehold).

### Meta moments (where, M14a)
Rare: about one an hour. Never inside the prologue's dark moments or a boss
fight.
- The seal of a gate locked by Act 1 reads, as an inscription:
  "As a large language model, I'm afraid I can't open this gate."
- Sigrun, after the act (built): "In the old songs the mentor dies at the end
  of the first act. I checked the script. I'm in luck - I'm a trainer."
- The nameless grave and its naming quest; the "kill ten" journal entry.
- The journal at the end of M14a's content: "Act II is being written right
  now."

### Sample lines (draft, DE + EN)
| Who | EN | DE |
|---|---|---|
| Edda (P1) | "Up. They're coming up from the graveyard, and they're not walking like the dead." | „Hoch mit dir. Sie kommen vom Friedhof herauf, und sie gehen nicht wie Tote.“ |
| Edda (P3) | "Your hand. It's glowing. Don't look at it, walk." | „Deine Hand. Sie glüht. Schau nicht hin, lauf.“ |
| The Reeve (P6, intro) | "Toll." | „Zoll.“ |
| Sigrun (P7) | "Show me your hand. ... No. Not you too." | „Zeig mir deine Hand. ... Nein. Nicht auch du.“ |
| Sigrun (a1_call) | "A shard of the Rune is in you. It won't come out. It will teach you, if you let it." | „In dir steckt ein Splitter der Rune. Er geht nicht mehr heraus. Er lehrt dich, wenn du ihn lässt.“ |
| Sigrun (a1_spire) | "Aldric. He taught me my first rune. He said a binding is a promise." | „Aldric. Er hat mir meine erste Rune beigebracht. Er sagte, eine Bindung ist ein Versprechen.“ |
| Maren | "Sigrun teaches walls. I teach what the walls are for." | „Sigrun lehrt Mauern. Ich lehre, wofür die Mauern da sind.“ |
| Hild | "The roots under the Charwood are warm. Roots should never be warm." | „Die Wurzeln unter dem Kohlwald sind warm. Wurzeln sollten nie warm sein.“ |
| Ylva | "Another refugee with a glowing hand. Drink this. It won't help with the hand." | „Noch ein Flüchtling mit glühender Hand. Trink das. Gegen die Hand hilft es nicht.“ |
| Tova | "Nobody comes down from the Stormwatch alone." | „Niemand kommt allein von der Sturmwarte herunter.“ |

### Writing rules
- German says "du"; nouns for the hero stay gender-neutral in both languages.
- One thought per dialogue box, at most two sentences; three to five boxes
  per conversation.
- Answer options are short (at most six words) and say what the hero means,
  not what they will literally say.
- Both languages are written, not translated; a joke may differ per language.
- Names: Runehold, Ashwick/Aschwick, Sigrun Runewright, the Runebound / die
  Runengebundenen; the event is the Breaking / das Zerbrechen der Rune, the
  Act 3 zone is the Breach / Der Bruch (keep them apart).
- Lore that already exists stays true; new text builds on it.

### Co-op and the story
- Story progress belongs to the character (`characters[i].story`), never to a
  world flag: online, the server's flags are not the character's.
- Kill, boss, reach and enter steps count for every hero present (the 60 m
  reward radius). Talk, read, collect and interact steps are personal.
- A story boss the server has already killed comes back while a present hero
  still needs it; only those heroes get its guaranteed legendary.
- Camera pans run on each machine on its own and never pause the world.
- A new character that goes online before finishing the prologue skips it.

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
  player-facing text is a key in a translation table. Decided in M12: JSON
  tables under `resources/i18n/` (`{key: {en, de}}`), loaded at runtime by
  `Texts` into Godot's TranslationServer (CSV was ruled out because Godot
  imports CSVs itself and writes generated files next to them). Settings ->
  Gameplay -> Language (auto = the system language).
- Both languages are written, never machine-translated. A joke is rewritten
  for each language when a pun does not carry over.
- From M12 on (the first lore texts) every new text is bilingual. The
  existing UI follows in M14.
