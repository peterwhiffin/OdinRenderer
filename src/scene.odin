package main

import hm "core:container/handle_map"
import la "core:math/linalg"
import b3 "vendor:box3d"
import vk "vendor:vulkan"


scene_init :: proc(s: ^Scene) {
	hm.dynamic_init(&s.entities, context.allocator)
}

scene_create_default :: proc(s: ^Scene, ren: ^Renderer, res: ^Resources, p: ^Physics) {
	s.name = "TestScene"
	scene_init(s)

	eh, e := scene_get_new_entity(s)
	set_scale(&e.transform, {100.0, 1.0, 100.0})
	mr := entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	set_scale(&e.transform, {1.0, 100.0, 100.0})
	set_position(&e.transform, {100.0, 100.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	set_scale(&e.transform, {1.0, 100.0, 100.0})
	set_position(&e.transform, {-100.0, 100.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	set_scale(&e.transform, {100.0, 100.0, 1.0})
	set_position(&e.transform, {0.0, 100.0, 100.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	set_scale(&e.transform, {100.0, 100.0, 1.0})
	set_position(&e.transform, {0.0, 100.0, -100.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	e.name = "Red"
	set_position(&e.transform, {0.0, 10.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {1.0, 0.0, 0.0, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	e.name = "Green"
	set_position(&e.transform, {1.5, 20.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {0.0, 1.0, 0.0, 1.0}
	entity_add_rigidbody(s, p, e, .staticBody)

	eh, e = scene_get_new_entity(s)
	e.name = "Sponza"
	set_position(&e.transform, {1.5, 20.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = res.mesh_map["Sponza.gltf"]
	mr.color = {1.0, 1.0, 1.0, 1.0}
}

scene_update_transforms :: proc(s: ^Scene) {
	profile_scoped()

	it := hm.iterator_make(&s.entities)

	for e, h in hm.iterate(&it) {
		if e.transform.is_dirty do update_transform_matrices(e, &s.entities)

		if .MESH_RENDERER in e.flags {
			e.mesh_renderer.normal_matrix = la.matrix4_inverse_transpose_f32(
				e.transform.world_transform,
			)
		}
	}
}

scene_get_new_entity :: proc(s: ^Scene) -> (Handle, ^Entity) {
	eh := hm.add(&s.entities, Entity{})
	e := hm.get(&s.entities, eh)
	e.name = "New Entity"
	e.flags += {.TRANSFORM}
	e.children = make([dynamic]Handle)
	e.transform.entity = eh
	set_scale(&e.transform, {1.0, 1.0, 1.0})
	set_euler_angles(&e.transform, {0.0, 0.0, 0.0})
	return eh, e
}

entity_add_mesh :: proc(s: ^Scene, e: ^Entity, ren: ^Renderer, res: ^Resources) -> ^Mesh_Renderer {
	e.flags += {.MESH_RENDERER}
	mr := &e.mesh_renderer
	mr.uniform_buffers = make([]Buffer, FIF)
	mr.desc_sets = make([]vk.DescriptorSet, FIF)
	mr.mesh = res.mesh_map["cube.gltf"]
	mr.color = {1.0, 1.0, 1.0, 1.0}

	for &buf in mr.uniform_buffers {
		buf = create_buffer(
			ren,
			size_of(Mesh_Uniforms),
			{.UNIFORM_BUFFER},
			{.HOST_ACCESS_SEQUENTIAL_WRITE, .HOST_ACCESS_ALLOW_TRANSFER_INSTEAD, .MAPPED},
		)
	}

	descriptor_set_create_mesh(ren, e)

	return mr
}

entity_add_rigidbody_default :: proc(
	s: ^Scene,
	p: ^Physics,
	e: ^Entity,
	type: b3.BodyType,
) -> ^Rigidbody {
	e.flags += {.RIGIDBODY}
	physics_create_rigidbody(p, e, type)
	return &e.rigidbody
}

entity_add_rigidbody_box :: proc(
	s: ^Scene,
	p: ^Physics,
	e: ^Entity,
	hull: ^b3.BoxHull,
	type: b3.BodyType,
) -> ^Rigidbody {
	e.flags += {.RIGIDBODY}
	physics_create_rigidbody(p, e, hull, type)
	return &e.rigidbody
}

entity_add_rigidbody :: proc {
	entity_add_rigidbody_default,
	entity_add_rigidbody_box,
}
