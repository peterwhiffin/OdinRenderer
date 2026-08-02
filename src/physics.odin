package main

import hm "core:container/handle_map"
import "core:math/linalg"
import b3 "vendor:box3d"

physics_init :: proc(p: ^Physics) {
	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0.0, -10.0, 0.0}
	p.world = b3.CreateWorld(world_def)
}

physics_create_rigidbody_box :: proc(
	p: ^Physics,
	e: ^Entity,
	hull: ^b3.BoxHull,
	type: b3.BodyType = .staticBody,
) {
	bd := b3.DefaultBodyDef()
	bd.position = e.transform.pos
	bd.rotation = e.transform.rot
	bd.type = type
	bd.enableSleep = true
	e.rigidbody.body_id = b3.CreateBody(p.world, bd)
	sd := b3.DefaultShapeDef()
	e.rigidbody.shape_id = b3.CreateHullShape(e.rigidbody.body_id, sd, &hull.base)
}

physics_create_rigidbody_default :: proc(
	p: ^Physics,
	e: ^Entity,
	type: b3.BodyType = .staticBody,
) {
	sd := b3.DefaultShapeDef()
	box_hull := b3.MakeBoxHull(
		1.0 * e.transform.scale.x,
		1.0 * e.transform.scale.y,
		1.0 * e.transform.scale.z,
	)
	physics_create_rigidbody_box(p, e, &box_hull, type)
}

physics_create_rigidbody :: proc {
	physics_create_rigidbody_default,
	physics_create_rigidbody_box,
}

physics_update_positions :: proc(p: ^Physics, s: ^Scene, dt: f32) {
	profile_scoped()
	it := hm.iterator_make(&s.entities)
	for e, h in hm.iterate(&it) {
		if .RIGIDBODY in e.flags {
			type := b3.Body_GetType(e.rigidbody.body_id)

			if type == .staticBody {
				r := linalg.quaternion_from_euler_angles(
					e.transform.rot.y,
					e.transform.rot.x,
					e.transform.rot.z,
					.YXZ,
				)

				b3.Body_SetTransform(e.rigidbody.body_id, e.transform.pos, r)
			} else {
				new_pos: f32
				set_position(&e.transform, b3.Body_GetPosition(e.rigidbody.body_id))
				q := b3.Body_GetRotation(e.rigidbody.body_id)
				set_rotation(&e.transform, q)
			}
		}
	}
}

physics_update :: proc(p: ^Physics, s: ^Scene, dt: f32) {
	profile_scoped()
	p.time_accum += dt

	for p.time_accum >= PHYSICS_TIMESTEP {
		profile_scoped("Physics Step")
		p.time_accum -= PHYSICS_TIMESTEP
		b3.World_Step(p.world, PHYSICS_TIMESTEP, 4)
	}

	physics_update_positions(p, s, dt)
}
