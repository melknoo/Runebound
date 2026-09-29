"""RUNEBOUND talent trees data -> resources/talents/*.tres.

The trees are authored here as tables (easier to review and retune as a whole)
and written as TalentData resources the game loads. Re-run after editing:
  python tools/talents/generate_talents.py
M10: one tree per class (TalentData.class_id). Each tree has three branches
(0, 1, 2); their names and colours live on the class (ClassData.talent_branches
/ talent_colors). Tier 0-3 opens at 0/3/6/10 points spent in the branch
(TalentData.TIER_POINTS).
  Runebreaker (tank):       0 Bulwark, 1 Earthshaker, 2 Runic Warden
  Elementalist (damage):    0 Storm, 1 Ember, 2 Frost
Talents whose ability or stat arrives later in M10 are listed already; their
power / stat is read by the code that comes with the ability.
"""
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "resources", "talents")

# id, name, branch, tier, max_rank, stat, per_rank, power, description
TREES = {
    "runebreaker": [
        # --- Bulwark: block, threat, damage taken ------------------------------------
        ("runic_plate", "Runic Plate", 0, 0, 3, "max_hp", 15.0, "", "+{value} maximum health."),
        ("stalwart", "Stalwart", 0, 0, 3, "dr_pct", 3.0, "", "Take {value}% less damage."),
        ("shield_wall", "Shield Wall", 0, 1, 2, "block_pct", 5.0, "", "Rune Wall blocks {value}% more of a frontal hit."),
        ("provoker", "Provoker", 0, 1, 2, "taunt_duration", 1.0, "", "Your taunts hold {value} s longer."),
        ("unbroken", "Unbroken", 0, 1, 1, "", 0.0, "unbroken",
         "Dodging through an attack grants a 15-health barrier (8 s cooldown)."),
        ("riposte", "Riposte", 0, 2, 1, "", 0.0, "riposte",
         "A parry's rune counter strikes every enemy within 2.5 m and grants 15 Resonance."),
        ("bastion", "Bastion", 0, 2, 2, "aegis_pct", 5.0, "", "Warding Rune reduces damage by {value}% more."),
        ("unyielding", "Unyielding", 0, 3, 1, "", 0.0, "unyielding",
         "Below 30% health you take 30% less damage."),
        # --- Earthshaker: Rune Cleave, Earthbreaker, Warden's Leap -------------------
        ("heavy_hands", "Heavy Hands", 1, 0, 3, "cleave_dmg_pct", 8.0, "", "Rune Cleave deals +{value}% damage."),
        ("earthshaker", "Earthshaker", 1, 0, 2, "eb_cost_reduce", 8.0, "", "Earthbreaker costs {value} less Resonance."),
        ("molten_core", "Molten Core", 1, 1, 1, "", 0.0, "molten_core", "Earthbreaker sets every enemy it hits ablaze (Burn)."),
        ("aftershock", "Aftershock", 1, 1, 2, "eb_radius", 0.5, "", "Earthbreaker's area grows by {value} m."),
        ("wide_arc", "Wide Arc", 1, 1, 2, "cleave_radius_pct", 15.0, "", "Rune Cleave reaches {value}% further."),
        ("quake_leap", "Quake Leap", 1, 2, 1, "", 0.0, "quake_leap",
         "Warden's Leap lands like Earthbreaker: its shockwave staggers heavily."),
        ("hold_the_line", "Hold the Line", 1, 2, 2, "aggro_dmg_pct", 8.0, "",
         "+{value}% damage to enemies that are attacking you."),
        ("tectonic", "Tectonic", 1, 3, 1, "", 0.0, "tectonic", "Earthbreaker taunts every enemy it hits for 3 s."),
        # --- Runic Warden: Resonance, barrier, the burst -----------------------------
        ("resonant_strikes", "Resonant Strikes", 2, 0, 3, "resonance_pct", 10.0, "", "+{value}% Resonance gained."),
        ("steadfast", "Steadfast", 2, 0, 2, "block_res", 3.0, "", "Every hit Rune Wall blocks grants {value} more Resonance."),
        ("runic_guard", "Runic Guard", 2, 1, 1, "", 0.0, "runic_guard",
         "Unlocks Runic Guard: spend 30 Resonance for a barrier that absorbs 40 damage (+1 per level) for 4 s."),
        ("warding_runes", "Warding Runes", 2, 1, 2, "guard_amount", 15.0, "", "Runic Guard absorbs {value} more damage."),
        ("glacial_bulwark", "Glacial Bulwark", 2, 1, 1, "", 0.0, "glacial_bulwark", "Enemies that strike your Runic Guard are Chilled."),
        ("resonance_burst", "Resonance Burst", 2, 2, 1, "", 0.0, "resonance_burst",
         "Unlocks Resonance Burst: spend all Resonance (50+) in a 4 m nova, 0.7 damage per point, heavy stagger."),
        ("binding_chains", "Binding Chains", 2, 2, 2, "tether_cd_pct", 15.0, "", "Rune Chain cooldown -{value}%."),
        ("aegis_of_runes", "Aegis of Runes", 2, 3, 1, "", 0.0, "aegis_of_runes",
         "Runic Guard also shields allies within 6 m for half its amount."),
    ],
    "elementalist": [
        # --- Storm: lightning, tempo ---------------------------------------------------
        ("static_charge", "Static Charge", 0, 0, 3, "crit_pct", 3.0, "", "+{value}% critical chance."),
        ("quickstep", "Quickstep", 0, 0, 2, "storm_cd_pct", 12.0, "", "Storm Step cooldown -{value}%."),
        ("arc_conduit", "Arc Conduit", 0, 1, 2, "chain_jumps", 1.0, "", "Chain Spark jumps to {value} additional enemy."),
        ("galvanize", "Galvanize", 0, 1, 3, "shocked_dmg_pct", 8.0, "", "+{value}% damage to Shocked enemies."),
        ("overload", "Overload", 0, 1, 1, "", 0.0, "overload", "Storm Step's end point Shocks every enemy within 2.5 m."),
        ("thunderclap", "Thunderclap", 0, 2, 1, "", 0.0, "thunderclap",
         "Chain Spark's last target bursts, dealing 60% of the hit to enemies within 2 m."),
        ("storm_surge", "Storm Surge", 0, 2, 2, "lightning_res_pct", 15.0, "", "+{value}% Aether from lightning hits."),
        ("eye_of_the_storm", "Eye of the Storm", 0, 3, 1, "", 0.0, "eye_of_the_storm",
         "Storm Step refunds 20% of its cooldown for every enemy it passes through."),
        # --- Ember: fire, damage over time --------------------------------------------
        ("kindling", "Kindling", 1, 0, 3, "burn_pct", 20.0, "", "Burn deals +{value}% damage."),
        ("searing_lance", "Searing Lance", 1, 0, 3, "ember_dmg_pct", 8.0, "", "Ember Lance deals +{value}% damage."),
        ("split_lance", "Split Lance", 1, 1, 1, "", 0.0, "split_lance",
         "Ember Lance splits into two half-damage lances on its first hit."),
        ("piercing_heat", "Piercing Heat", 1, 1, 1, "ember_pierce", 1.0, "", "Ember Lance pierces {value} additional enemy."),
        ("cinderfall", "Cinderfall", 1, 1, 1, "", 0.0, "cinderfall", "Ember Fall leaves burning ground for 3 s."),
        ("wildfire", "Wildfire", 1, 2, 1, "", 0.0, "wildfire", "A Burning enemy that dies spreads Burn to enemies within 3 m."),
        ("fuel_the_fire", "Fuel the Fire", 1, 2, 2, "burning_dmg_pct", 10.0, "", "+{value}% damage to Burning enemies."),
        ("phoenix_burst", "Phoenix Burst", 1, 3, 1, "", 0.0, "phoenix_burst",
         "Ember Lance bursts where it ends: 50% of its damage to enemies within 2 m, and Burn."),
        # --- Frost: control ---------------------------------------------------------------
        ("frost_ward", "Frost Ward", 2, 0, 2, "rune_arm_reduce", 0.2, "", "Fracture Rune arms {value} s faster."),
        ("aether_flow", "Aether Flow", 2, 0, 3, "resonance_pct", 10.0, "", "+{value}% Aether gained."),
        ("shatter", "Shatter", 2, 1, 3, "chilled_dmg_pct", 8.0, "", "+{value}% damage to Chilled enemies."),
        ("deep_freeze", "Deep Freeze", 2, 1, 1, "", 0.0, "deep_freeze", "Frost Nova roots the enemies it Chills for 1 s."),
        ("rune_mastery", "Rune Mastery", 2, 1, 2, "rune_radius", 0.5, "", "Fracture Rune's area grows by {value} m."),
        ("echo_rune", "Echo Rune", 2, 2, 1, "", 0.0, "echo_rune",
         "Fracture Rune detonates a second time a moment later, at half damage."),
        ("cold_snap", "Cold Snap", 2, 2, 2, "chill_duration", 0.5, "", "Chill lasts {value} s longer."),
        ("absolute_zero", "Absolute Zero", 2, 3, 1, "", 0.0, "absolute_zero",
         "An enemy Chilled three times within 6 s freezes solid for 2 s."),
    ],
}

HEADER = '''[gd_resource type="Resource" script_class="TalentData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/progression/talent_data.gd" id="1"]

[resource]
script = ExtResource("1")
'''


def esc(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


FIELDS = ('id = &"{id}"\n'
          'display_name = "{name}"\n'
          'class_id = &"{cls}"\n'
          'branch = {branch}\n'
          'tier = {tier}\n'
          'max_rank = {ranks}\n'
          'stat = &"{stat}"\n'
          'per_rank = {per_rank}\n'
          'power = &"{power}"\n'
          'description = "{desc}"\n')


def main():
    os.makedirs(OUT, exist_ok=True)
    keep = set()
    total = 0
    for cls, table in TREES.items():
        for tid, name, branch, tier, ranks, stat, per_rank, power, desc in table:
            assert tid + ".tres" not in keep, "talent id used twice: " + tid
            body = HEADER + FIELDS.format(id=tid, name=esc(name), cls=cls, branch=branch, tier=tier, ranks=ranks,
                                          stat=stat, per_rank=repr(float(per_rank)), power=power, desc=esc(desc))
            keep.add(tid + ".tres")
            with open(os.path.join(OUT, tid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
                f.write(body)
            total += 1
        # every tier must be reachable: tier t needs TIER_POINTS[t] ranks below it in its branch
        for branch in range(3):
            for tier, need in ((1, 3), (2, 6), (3, 10)):
                below = sum(r[4] for r in table if r[2] == branch and r[3] < tier)
                has_tier = any(r[2] == branch and r[3] == tier for r in table)
                assert not has_tier or below >= need, "%s branch %d tier %d unreachable (%d < %d)" % (
                    cls, branch, tier, below, need)
    for fname in os.listdir(OUT):   # drop nodes removed from the tables
        if fname.endswith(".tres") and fname not in keep:
            os.remove(os.path.join(OUT, fname))
    print("talents: %d nodes in %d trees -> resources/talents/" % (total, len(TREES)))


if __name__ == "__main__":
    main()
