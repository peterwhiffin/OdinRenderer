package main

import "core:math/linalg"

update_transform_matrices :: proc(t: ^Transform) {
	rads: [3]f32 = linalg.to_radians(t.rot)
	q := linalg.quaternion_from_euler_angles_f32(rads.y, rads.x, rads.z, .YXZ)

	// R := linalg.matrix4_from_euler_angles_xyz(rads.x, rads.y, rads.z)
	T := linalg.matrix4_translate(t.pos)
	R := linalg.matrix4_from_quaternion(q)
	S := linalg.matrix4_scale(t.scale)

	t.world_transform = T * R * S
	t.is_dirty = false
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

set_rotation :: proc(t: ^Transform, rot: [3]f32) {
	t.rot = rot
	t.is_dirty = true
}

set_scale :: proc(t: ^Transform, scale: [3]f32) {
	t.scale = scale
	t.is_dirty = true
}

update_transforms :: proc()
