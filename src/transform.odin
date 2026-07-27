package main

import "core:fmt"
import "core:math"
import "core:math/linalg"

update_transform_matrices :: proc(t: ^Transform) {

	// rads: [3]f32 = linalg.to_radians(t.rot)
	// q := linalg.quaternion_from_euler_angles_f32(rads.y, rads.x, rads.z, .YXZ)
	T := linalg.matrix4_translate(t.pos)
	R := linalg.matrix4_from_quaternion(t.rot)
	S := linalg.matrix4_scale(t.scale)
	t.world_transform = T * R * S

	if t.parent != nil {
		t.world_transform = t.parent.world_transform * t.world_transform
	}

	for &child in t.children {
		update_transform_matrices(child)
	}

	t.is_dirty = false
}

unset_parent :: proc(t: ^Transform) {

}

set_parent :: proc(t: ^Transform, parent: ^Transform) {

}

get_right :: proc(t: ^Transform) -> [3]f32 {
	return t.world_transform[0].xyz
}

get_up :: proc(t: ^Transform) -> [3]f32 {
	return t.world_transform[1].xyz
}

get_forward :: proc(t: ^Transform) -> [3]f32 {
	return t.world_transform[2].xyz
}

set_position :: proc(t: ^Transform, pos: [3]f32) {
	t.pos = pos
	t.is_dirty = true
}

set_rotation :: proc(t: ^Transform, rot: quaternion128) {
	t.rot = linalg.quaternion_normalize(rot)

	ex, ey, ez := linalg.euler_angles_from_quaternion(t.rot, .XYZ)

	ex = linalg.to_degrees(ex)
	ey = linalg.to_degrees(ey)
	ez = linalg.to_degrees(ez)

	t.euler_angles = {ex, ey, ez}

	t.is_dirty = true
}

set_euler_angles :: proc(t: ^Transform, angles: [3]f32) {
	t.euler_angles = angles
	r := linalg.to_radians(angles)
	q := linalg.quaternion_from_euler_angles(r.y, r.x, r.z, .YXZ)
	t.rot = linalg.quaternion_normalize(q)
	t.is_dirty = true
}

set_scale :: proc(t: ^Transform, scale: [3]f32) {
	t.scale = scale
	t.is_dirty = true
}
