package main

import "core:fmt"
import "core:log"
import la "core:math/linalg"
import vk "vendor:vulkan"

scene_init :: proc(s: ^Scene, ren: ^Renderer, res: ^Resources, p: ^Physics) {
	s.entities.data = make([]Entity, 1000)
	e := scene_get_new_entity(s)
	set_scale(&e.transform, {100.0, 1.0, 100.0})
	mr := entity_add_mesh(s, e, ren, res)
	mr.mesh = &res.meshes.data[0]
	mr.color = {0.3, 0.3, 0.3, 1.0}
	entity_add_rigidbody(s, p, e)

	e = scene_get_new_entity(s)
	set_position(&e.transform, {0.0, 10.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = &res.meshes.data[0]
	mr.color = {1.0, 0.0, 0.0, 1.0}

	entity_add_rigidbody(s, p, e)

	e = scene_get_new_entity(s)
	set_position(&e.transform, {1.5, 20.0, 0.0})
	mr = entity_add_mesh(s, e, ren, res)
	mr.mesh = &res.meshes.data[0]
	mr.color = {0.0, 1.0, 0.0, 1.0}
	entity_add_rigidbody(s, p, e)
}

scene_update_transforms :: proc(s: ^Scene) {
	for i in 0 ..< s.entities.count {
		e := &s.entities.data[i]
		// fmt.println("Updateing transform! ", i)
		if e.transform.is_dirty do update_transform_matrices(&e.transform)

		if .MESH_RENDERER in e.flags {
			e.mesh_renderer.normal_matrix = la.matrix4_inverse_transpose_f32(
				e.transform.world_transform,
			)
		}
	}
}

scene_get_new_entity :: proc(s: ^Scene) -> ^Entity {
	e := &s.entities.data[s.entities.count]
	s.entities.count += 1
	e.name = "New Entity"
	e.transform.children = make([dynamic]^Transform)
	e.transform.entity = e
	set_scale(&e.transform, {1.0, 1.0, 1.0})
	return e
}

entity_add_mesh :: proc(s: ^Scene, e: ^Entity, ren: ^Renderer, res: ^Resources) -> ^Mesh_Renderer {
	e.flags += {.MESH_RENDERER}
	mr := &e.mesh_renderer
	mr.uniform_buffers = make([]Buffer, FIF)
	mr.desc_sets = make([]vk.DescriptorSet, FIF)
	mr.mesh = &res.meshes.data[0]
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

entity_add_rigidbody :: proc(s: ^Scene, p: ^Physics, e: ^Entity) {
	e.flags += {.RIGIDBODY}
	physics_create_rigidbody(p, e)
}

main :: proc() {
	win: Window
	input: Input
	ren: Renderer
	phys: Physics
	res: Resources
	editor: Editor
	scene: Scene


	context.logger = log.create_console_logger()
	g_ctx = context

	window_init(&win, &input)
	resources_init(&res)
	renderer_init(&ren, &win, &res)
	physics_init(&phys)
	scene_init(&scene, &ren, &res, &phys)
	editor_init(&editor, &win, &input, &ren, &res, &phys, &scene)

	update_transform_matrices(&editor.cam.transform)

	for !win.should_close {
		time_update(&win)
		poll_events(&ren, &win, &input, &editor.cam.camera)
		input_update(&input)
		physics_update(&phys, &scene, f32(win.delta_time))
		scene_update_transforms(&scene)
		editor_update(&editor)
		draw_frame(&ren, &win, &editor.cam.camera, &scene)
		swapchain_update(&ren, &win)
		sleep_spin(&win)
	}
}
