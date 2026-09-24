"""RUNEBOUND M07 talent tree data -> resources/talents/*.tres.

The tree is authored here as a table (easier to review and retune as a whole)
and written as TalentData resources the game loads. Re-run after editing:
  python tools/talents/generate_talents.py
Branches: 0 Storm, 1 Ember, 2 Runic Warden. Tier 0-3 opens at 0/3/6/10
points spent in the branch (TalentData.TIER_POINTS).
"""
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "resources", "talents")
CLASS = "runebreaker"  # M07b: every node of this table belongs to one class (TalentData.class_id)

# id, name, branch, tier, max_rank, stat, per_rank, power, description
TALENTS = [
    # --- Storm ---------------------------------------------------------------------
    ("static_charge", "Static Charge", 0, 0, 3, "crit_pct", 3.0, "", "+{value}% critical chance."),
    ("quickstep", "Quickstep", 0, 0, 2, "storm_cd_pct", 12.0, "", "Storm Step cooldown -{value}%."),
    ("arc_conduit", "Arc Conduit", 0, 1, 2, "chain_jumps", 1.0, "", "Chain Spark jumps to {value} additional enemy."),
    ("galvanize", "Galvanize", 0, 1, 3, "shocked_dmg_pct", 8.0, "", "+{value}% damage to Shocked enemies."),
    ("overload", "Overload", 0, 1, 1, "", 0.0, "overload", "Storm Step's end point Shocks every enemy within 2.5 m."),
    ("thunderclap", "Thunderclap", 0, 2, 1, "", 0.0, "thunderclap",
     "Chain Spark's last target bursts, dealing 60% of the hit to enemies within 2 m."),
    ("storm_surge", "Storm Surge", 0, 2, 2, "lightning_res_pct", 15.0, "", "+{value}% Resonance from lightning hits."),
    ("eye_of_the_storm", "Eye of the Storm", 0, 3, 1, "", 0.0, "eye_of_the_storm",
     "Storm Step refunds 20% of its cooldown for every enemy it passes through."),
    # --- Ember ---------------------------------------------------------------------
    ("kindling", "Kindling", 1, 0, 3, "burn_pct", 20.0, "", "Burn deals +{value}% damage."),
    ("searing_lance", "Searing Lance", 1, 0, 3, "ember_dmg_pct", 8.0, "", "Ember Lance deals +{value}% damage."),
    ("split_lance", "Split Lance", 1, 1, 1, "", 0.0, "split_lance",
     "Ember Lance splits into two half-damage lances on its first hit."),
    ("piercing_heat", "Piercing Heat", 1, 1, 1, "ember_pierce", 1.0, "", "Ember Lance pierces {value} additional enemy."),
    ("molten_core", "Molten Core", 1, 1, 1, "", 0.0, "molten_core", "Earthbreaker sets every enemy it hits ablaze (Burn)."),
    ("wildfire", "Wildfire", 1, 2, 1, "", 0.0, "wildfire", "A Burning enemy that dies spreads Burn to enemies within 3 m."),
    ("fuel_the_fire", "Fuel the Fire", 1, 2, 2, "burning_dmg_pct", 10.0, "", "+{value}% damage to Burning enemies."),
    ("phoenix_burst", "Phoenix Burst", 1, 3, 1, "", 0.0, "phoenix_burst",
     "Ember Lance bursts where it ends: 50% of its damage to enemies within 2 m, and Burn."),
    # --- Runic Warden ------------------------------------------------------------------
    ("runic_plate", "Runic Plate", 2, 0, 3, "max_hp", 15.0, "", "+{value} maximum health."),
    ("resonant_strikes", "Resonant Strikes", 2, 0, 3, "resonance_pct", 10.0, "", "+{value}% Resonance gained."),
    ("runic_guard", "Runic Guard", 2, 1, 1, "", 0.0, "runic_guard",
     "Unlocks Runic Guard (5): spend 30 Resonance for a barrier that absorbs 40 damage (+1 per level) for 4 s."),
    ("earthshaker", "Earthshaker", 2, 1, 2, "eb_cost_reduce", 8.0, "", "Earthbreaker costs {value} less Resonance."),
    ("frost_ward", "Frost Ward", 2, 1, 2, "rune_arm_reduce", 0.2, "", "Fracture Rune arms {value} s faster."),
    ("glacial_bulwark", "Glacial Bulwark", 2, 2, 1, "", 0.0, "glacial_bulwark", "Enemies that strike your Runic Guard are Chilled."),
    ("resonance_burst", "Resonance Burst", 2, 2, 1, "", 0.0, "resonance_burst",
     "Unlocks Resonance Burst (6): spend all Resonance (50+) in a 4 m nova, 0.7 damage per point, heavy stagger."),
    ("unbroken", "Unbroken", 2, 3, 1, "", 0.0, "unbroken",
     "Dodging through an attack grants a 15-health barrier (8 s cooldown)."),
]

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
    for tid, name, branch, tier, ranks, stat, per_rank, power, desc in TALENTS:
        body = HEADER + FIELDS.format(id=tid, name=esc(name), cls=CLASS, branch=branch, tier=tier, ranks=ranks, stat=stat,
                                      per_rank=repr(float(per_rank)), power=power, desc=esc(desc))
        keep.add(tid + ".tres")
        with open(os.path.join(OUT, tid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
    for fname in os.listdir(OUT):   # drop nodes removed from the table
        if fname.endswith(".tres") and fname not in keep:
            os.remove(os.path.join(OUT, fname))
    print("talents: %d nodes -> resources/talents/" % len(TALENTS))


if __name__ == "__main__":
    main()
