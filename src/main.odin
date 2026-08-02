package main

import "base:runtime"
import "core:log"


main :: proc() {
	profile_init()
	defer profile_clean()
	profile_scoped()

	profile_begin("Initialize")
	win: Window
	input: Input
	ren: Renderer
	phys: Physics
	res: Resources
	editor: Editor
	scene: Scene
	win.input = &input

	context.logger = log.create_console_logger()
	g_ctx = context

	window_init(&win, &input)
	resources_init(&res)
	renderer_init(&ren, &win, &res)
	physics_init(&phys)
	editor_init(&editor, &win, &input, &ren, &res, &phys, &scene)
	load_scene("TestScene.scene", &scene, &res, &ren, &phys)
	time_update(&win)
	physics_update(&phys, &scene, f32(win.delta_time))
	free_all(context.temp_allocator)
	time_update(&win)
	profile_end("Initialize")

	for !win.should_close {
		profile_scoped("Frame")
		time_update(&win)
		poll_events(&ren, &win, &input, &editor.cam.camera)
		editor_update(&editor)
		physics_update(&phys, &scene, f32(win.delta_time))
		scene_update_transforms(&scene)
		draw_frame(&ren, &win, &editor.cam.camera, &scene)
		swapchain_update(&ren, &win)
		free_all(context.temp_allocator)
		sleep_spin(&win)
	}

}
