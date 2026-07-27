package main

import "core:math/linalg"
import b3 "vendor:box3d"

physics_init :: proc(p: ^Physics) {
	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0.0, -10.0, 0.0}
	p.world = b3.CreateWorld(world_def)
}

physics_create_rigidbody :: proc(p: ^Physics, e: ^Entity) {
	bd := b3.DefaultBodyDef()
	sd := b3.DefaultShapeDef()

	bd.position = e.transform.pos
	bd.type = .staticBody

	box_hull := b3.MakeBoxHull(
		1.0 * e.transform.scale.x,
		1.0 * e.transform.scale.y,
		1.0 * e.transform.scale.z,
	)

	e.rigidbody.body_id = b3.CreateBody(p.world, bd)
	e.rigidbody.shape_id = b3.CreateHullShape(e.rigidbody.body_id, sd, &box_hull.base)
}

physics_update_positions :: proc(p: ^Physics, s: ^Scene, dt: f32) {
	for i in 0 ..< s.entities.count {
		e := &s.entities.data[i]
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
				ry, rx, rz := linalg.euler_angles_from_quaternion(q, .YXZ)
				set_rotation(&e.transform, q)
				// set_rotation(&e.transform, {linalg.euler_angles_from_quaternion(q, .XYZ)})
			}
		}
	}
}

physics_update :: proc(p: ^Physics, s: ^Scene, dt: f32) {

	p.time_accum += dt

	if p.time_accum >= PHYSICS_TIMESTEP {
		p.time_accum -= PHYSICS_TIMESTEP
		b3.World_Step(p.world, PHYSICS_TIMESTEP, 4)

		physics_update_positions(p, s, dt)
	} else {
		physics_update_positions(p, s, dt)
	}
}
