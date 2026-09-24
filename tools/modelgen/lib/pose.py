"""Intent-based posing for rigid rigs (M06).

Generators key FK Euler dicts. Hand-guessing Eulers through three joints
does not land a sword where a hit volume is, so a pose may also carry
intents that this module resolves into those Euler values:

  "_reach.R": (wrist_target, pole)  analytic two-bone IK for upper_arm/forearm;
                                    `pole` is the direction the elbow bends to
  "_blade.R": direction             points hand.R's -Z axis (a weapon modeled
                                    along -Y at rest on a hanging hand bone)
  "_aim.<bone>": direction          points the bone's length (Y axis)

Targets and directions are armature space: +X = character's left, -Y =
forward, +Z = up (see pos() / way()). The chain is evaluated with Blender's
own formula (parent pose @ parent rest^-1 @ rest @ basis), so a solved pose
is exactly what the armature shows. Swings are minimal (no added twist).
"""
import math

from mathutils import Euler, Matrix, Vector


def pos(fwd=0.0, left=0.0, up=0.0):
    """Armature-space point from character-relative offsets (metres)."""
    return Vector((left, -fwd, up))


def way(fwd=0.0, left=0.0, up=0.0):
    """Armature-space unit direction from character-relative components."""
    return Vector((left, -fwd, up)).normalized()


class Poser:
    def __init__(self, arm_obj):
        bones = arm_obj.data.bones
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.length = {b.name: b.length for b in bones}

    @staticmethod
    def _basis(value):
        rot = value.get("rot") if isinstance(value, dict) else value
        loc = value.get("loc") if isinstance(value, dict) else None
        m = Euler(rot or (0.0, 0.0, 0.0), "XYZ").to_matrix().to_4x4()
        if loc is not None:
            m.translation = Vector(loc)
        return m

    def matrix(self, pose, name):
        """Armature-space pose matrix of `name` under the FK values in `pose`."""
        p = self.parent[name]
        basis = self._basis(pose.get(name, (0.0, 0.0, 0.0)))
        if p is None:
            return self.rest[name] @ basis
        return self.matrix(pose, p) @ self.rest[p].inverted() @ self.rest[name] @ basis

    def _frame(self, pose, name):
        """Pose matrix of `name` with its own basis = identity."""
        p = self.parent[name]
        if p is None:
            return self.rest[name].copy()
        return self.matrix(pose, p) @ self.rest[p].inverted() @ self.rest[name]

    def aim(self, pose, name, direction, axis=(0.0, 1.0, 0.0)):
        local = self._frame(pose, name).to_3x3().inverted() @ Vector(direction).normalized()
        q = Vector(axis).rotation_difference(local)
        pose[name] = tuple(q.to_euler("XYZ"))

    def reach(self, pose, side, target, pole):
        up, fore = "upper_arm." + side, "forearm." + side
        shoulder = self._frame(pose, up).translation
        l1, l2 = self.length[up], self.length[fore]
        d = Vector(target) - shoulder
        dist = max(min(d.length, (l1 + l2) * 0.999), abs(l1 - l2) + 1e-4)
        dn = d.normalized()
        a = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        bend = Vector(pole) - dn * Vector(pole).dot(dn)
        if bend.length < 1e-6:
            bend = dn.orthogonal()
        elbow = shoulder + dn * a + bend.normalized() * h
        self.aim(pose, up, elbow - shoulder)
        self.aim(pose, fore, (shoulder + dn * dist) - elbow)

    def apply(self, pose):
        """Resolve intents; returns a plain FK pose dict."""
        out = {k: v for k, v in pose.items() if not k.startswith("_")}
        for key in sorted(k for k in pose if k.startswith("_reach.")):
            target, pole = pose[key]
            self.reach(out, key.split(".", 1)[1], target, pole)
        for key in sorted(k for k in pose if k.startswith("_blade.")):
            self.aim(out, "hand." + key.split(".", 1)[1], pose[key], axis=(0.0, 0.0, -1.0))
        for key in sorted(k for k in pose if k.startswith("_aim.")):
            self.aim(out, key.split(".", 1)[1], pose[key])
        return out


def compatible(keys):
    """Rewrite rotation Eulers so each key is the closest equivalent of the
    previous key's (solved rotations may jump by 2*pi, which would make the
    interpolated clip spin the long way round)."""
    prev = {}
    out = []
    for frame, pose in sorted(keys, key=lambda kv: kv[0]):
        fixed = {}
        for bone, value in pose.items():
            is_dict = isinstance(value, dict)
            rot = value.get("rot") if is_dict else value
            if rot is not None and bone in prev:
                rot = tuple(Euler(rot, "XYZ").to_quaternion().to_euler("XYZ", prev[bone]))
            if rot is not None:
                prev[bone] = Euler(rot, "XYZ")
            fixed[bone] = ({**value, "rot": rot} if is_dict else rot)
        out.append((frame, fixed))
    return out
