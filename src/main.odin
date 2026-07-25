package main

import "core:fmt"
import "core:log"
import "core:math/linalg"

import "renderer"
import "window"

App :: struct {
	console_logger: log.Logger,
}

init_logger :: proc(app: ^App) {
	app.console_logger = log.create_console_logger()
}


main :: proc() {
	app: App
	win: window.Window
	input: window.Input
	ren: renderer.Renderer
	res: renderer.Resources
	editor: Editor

	init_logger(&app)
	context.logger = app.console_logger
	renderer.g_ctx = context

	window.init(&win, &input)
	renderer.resources_init(&res)
	renderer.init(&ren, &win, &res)
	editor_init(&editor, &win, &input, &ren, &res)

	update_transform_matrices(&editor.cam.transform)

	for !win.should_close {
		window.time_update(&win)
		window.poll_events(&win, &input)
		window.input_update(&input)
		editor_update(&editor)
		renderer.draw_frame(&ren, &win, &editor.cam.camera, &res.meshes.data[0])
		window.sleep_spin(&win)
	}
}
