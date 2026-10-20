class_name StoryBosses
extends Object
## M14a: story bosses come back online (user, 2026-10-20). On a co-op server
## the Colossus or the Vessel stays dead for everyone once beaten (a world
## flag), but a friend whose own story still needs it would never meet it.
## So the authority asks the heroes near the arena: while one of them has a
## story that lacks the beat `boss:<type>`, the boss stands again (the gates
## stay open). The server knows each hero's story from its CHARACTER message
## (proxies carry the QuestLog); offline the only hero is the local one.
## After a replay only the heroes that needed it get the boss's legendary.

## How long a beaten story boss stays down before a needing hero may wake it
## again (a CHARACTER with the new beat is on its way meanwhile).
const REARM := 20.0
## Meta on a server proxy: beats the server credited already ({beat: true}),
## so a CHARACTER that left the client before the kill can't wake the boss.
const CREDITED := &"story_credited"


## Does a hero within `radius` of `at` still need `boss` for its story?
static func needed_near(zone: ZoneBase, boss: String, at: Vector3, radius: float = ZoneBase.REWARD_RADIUS) -> bool:
	for p in zone.heroes_near(at, radius):
		if needs(p, boss):
			return true
	return false


## True when `hero` has a story that hasn't beaten `boss` yet.
static func needs(hero: Player, boss: String) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	var ql := QuestLog.of(hero)
	if not ql.active:
		return false
	var beat := "boss:" + boss
	return not ql.has_beat(beat) and not bool((hero.get_meta(CREDITED, {}) as Dictionary).get(beat, false))


## The heroes within the reward radius that needed `boss`, now credited (the
## server remembers it on their proxies at once; each client marks its own
## beat through its QuestDirector when the boss dies near it).
static func credit(zone: ZoneBase, boss: String, at: Vector3) -> Array[Player]:
	var out: Array[Player] = []
	for p in zone.heroes_near(at, ZoneBase.REWARD_RADIUS):
		if needs(p, boss):
			out.append(p)
			if p.net_role == Player.NetRole.PROXY:  # never the proxy's log itself: the server runs no quests
				var beats: Dictionary = (p.get_meta(CREDITED, {}) as Dictionary).duplicate()
				beats["boss:" + boss] = true
				p.set_meta(CREDITED, beats)
	return out
