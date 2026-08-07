package main
import "base:runtime"
import hm "core:container/handle_map"
import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:mem"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		lsd: int
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)


		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("--- %v allocations not freed: ---\n", len(track.allocation_map))

				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

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
	game: Game
	win.input = &input

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)
	g_ctx = context

	window_init(&win, &input)
	resources_init(&res)
	renderer_init(&ren, &win, &res)
	physics_init(&phys)
	// scene_create_default(&scene, &ren, &res, &phys)
	load_scene("TestScene.scene", &scene, &res, &ren, &phys, &win)
	game_init(&game, &scene, &input, &win, &phys)
	editor_init(&editor, &win, &input, &ren, &res, &phys, &scene, &game)
	time_update(&win)
	physics_update(&phys, &scene, f32(win.delta_time))
	free_all(context.temp_allocator)
	time_update(&win)
	profile_end("Initialize")

	for !win.should_close {
		profile_scoped("Frame")
		time_update(&win)
		poll_events(&ren, &win, &input, &editor, &game, &scene)
		cam := editor_update(&editor)
		physics_update(&phys, &scene, f32(win.delta_time))
		scene_update_transforms(&scene)
		draw_frame(&ren, &win, cam, &scene, &editor)
		swapchain_update(&ren, &win)
		free_all(context.temp_allocator)
		sleep_spin(&win)
	}

	when ODIN_DEBUG {
		clean(&editor)
	}
}

clean :: proc(editor: ^Editor) {
	delete(editor.scene.name)
	it := hm.iterator_make(&editor.scene.entities)

	for e, h in hm.iterate(&it) {
		delete(e.name)
		if .Mesh_Renderer in e.flags {
			delete(e.mesh_renderer.desc_sets)
			delete(e.mesh_renderer.uniform_buffers)
		}
	}

	delete(editor.ren.test_buff)

	xit := xar.iterator(&editor.res.meshes)

	for m, i in xar.iterate_by_ptr(&xit) {
		delete(m.submeshes)
	}

	delete(editor.ren.post_uniform_buffers)
	hm.dynamic_destroy(&editor.scene.entities)

	xar.destroy(&editor.res.images)
	xar.destroy(&editor.res.meshes)

	delete(editor.ren.swap_images)
	delete(editor.ren.fences)
	delete(editor.ren.semaphore_image)
	delete(editor.ren.semaphore_render)
	delete(editor.ren.picking_buffers)
	delete(editor.res.mesh_map)
	delete(editor.res.image_map)
	delete(editor.ren.desc_set_post)
	delete(editor.ren.command_buffers)
	delete(editor.ren.desc_set_pick)
	delete(editor.ren.forward_images)
}
