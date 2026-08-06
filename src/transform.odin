package main

import hm "core:container/handle_map"
import la "core:math/linalg"
import b3 "vendor:box3d"

update_transform_matrices_ptr :: proc(e: ^Entity, m: ^hm.Dynamic_Handle_Map(Entity, Handle)) {
	t := &e.transform

	T := la.matrix4_translate(t.pos)
	R := la.matrix4_from_quaternion(t.rot)
	S := la.matrix4_scale(t.scale)

	t.world_transform = T * R * S

	if p, ok := hm.get(m, e.parent); ok {
		t.world_transform = p.transform.world_transform * t.world_transform
	}

	if .Rigidbody in e.flags {
		type := b3.Body_GetType(e.rigidbody.body_id)
		if type == .staticBody {

			b3.Body_SetTransform(e.rigidbody.body_id, e.transform.pos, t.rot)
		}
	}


	for &child in e.children {
		ce := hm.get(m, child)
		update_transform_matrices(ce, m)
	}


	t.is_dirty = false
}

update_transform_matrices_handle :: proc(h: Handle, m: ^hm.Dynamic_Handle_Map(Entity, Handle)) {
	e := hm.get(m, h)
	t := &e.transform

	T := la.matrix4_translate(t.pos)
	R := la.matrix4_from_quaternion(t.rot)
	S := la.matrix4_scale(t.scale)

	t.world_transform = T * R * S

	if p, ok := hm.get(m, e.parent); ok {
		t.world_transform = p.transform.world_transform * t.world_transform
	}

	if .Rigidbody in e.flags {
		type := b3.Body_GetType(e.rigidbody.body_id)
		if type == .staticBody {

			b3.Body_SetTransform(e.rigidbody.body_id, e.transform.pos, t.rot)
		}
	}


	for &child in e.children {
		ce := hm.get(m, child)
		update_transform_matrices(ce, m)
	}


	t.is_dirty = false
}

update_transform_matrices :: proc {
	update_transform_matrices_ptr,
	update_transform_matrices_handle,
}

unset_parent :: proc(child: Handle, scene: ^Scene) {
	entity: ^Entity = hm.get(&scene.entities, child)
	parent_entity, ok := hm.get(&scene.entities, entity.parent)

	if !ok {
		return
	}

	for handle, i in parent_entity.children {
		if handle == child {
			unordered_remove(&parent_entity.children, i)
			break
		}
	}

	entity.parent = {}

	child_transform := &entity.transform
	parent_transform := &parent_entity.transform

	new_local_pos := parent_transform.pos + child_transform.pos
	new_local_rot := parent_transform.euler_angles + child_transform.euler_angles
	new_local_scale := parent_transform.scale * child_transform.scale

	set_position(child_transform, new_local_pos, scene)
	set_euler_angles(child_transform, new_local_rot, scene)
	set_scale(child_transform, new_local_scale, scene)
}

scale_from_matrix :: proc(m: ^la.Matrix4x4f32) -> [3]f32 {
	x := la.length(m[0].xyz)
	y := la.length(m[1].xyz)
	z := la.length(m[2].xyz)

	return {x, y, z}
}

set_parent :: proc(child: Handle, parent: Handle, scene: ^Scene) {
	entity: ^Entity = hm.get(&scene.entities, child)
	parent_entity: ^Entity = hm.get(&scene.entities, parent)

	unset_parent(child, scene)

	entity.parent = parent_entity.handle
	append(&parent_entity.children, child)

	child_transform := &entity.transform
	parent_transform := &parent_entity.transform

	// TODO: I think i can still compute the new locals from the parent locals instead of the inverse world matrix. Not sure
	parent_to_local :=
		la.matrix4_inverse(parent_transform.world_transform) * child_transform.world_transform
	new_local_pos: [3]f32 = {parent_to_local[3].x, parent_to_local[3].y, parent_to_local[3].z}
	new_local_rot := la.quaternion_from_matrix4(parent_to_local)
	new_local_scale := scale_from_matrix(&parent_to_local)

	set_position(child_transform, new_local_pos, scene) // parent->childEntityIds.push_back(child->entityID);// child->parentEntityID = parent->entityID;
	set_rotation(child_transform, new_local_rot, scene)
	set_scale(child_transform, new_local_scale, scene)
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

set_position :: proc(t: ^Transform, pos: [3]f32, scene: ^Scene) {
	t.pos = pos
	t.is_dirty = true
	update_transform_matrices(t.entity, &scene.entities)
}

set_rotation :: proc(t: ^Transform, rot: quaternion128, scene: ^Scene) {
	t.rot = la.quaternion_normalize(rot)

	ex, ey, ez := la.euler_angles_from_quaternion(t.rot, .XYZ)

	ex = la.to_degrees(ex)
	ey = la.to_degrees(ey)
	ez = la.to_degrees(ez)

	t.euler_angles = {ex, ey, ez}

	t.is_dirty = true
	update_transform_matrices(t.entity, &scene.entities)
}

set_euler_angles :: proc(t: ^Transform, angles: [3]f32, scene: ^Scene) {
	t.euler_angles = angles
	r := la.to_radians(angles)
	q := la.quaternion_from_euler_angles(r.y, r.x, r.z, .YXZ)
	t.rot = la.quaternion_normalize(q)
	t.is_dirty = true
	update_transform_matrices(t.entity, &scene.entities)
}

set_scale :: proc(t: ^Transform, scale: [3]f32, scene: ^Scene) {
	t.scale = scale
	t.is_dirty = true
	update_transform_matrices(t.entity, &scene.entities)
}
