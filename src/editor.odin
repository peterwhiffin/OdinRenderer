package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_sdl3"
import "../../odin-imgui/imgui_impl_vulkan"
import hm "core:container/handle_map"
import "core:math/linalg"
import "core:strings"
import b3 "vendor:box3d"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

Editor_Actions :: enum {
	MOVEMENT,
	M0,
	M1,
	SHIFT,
	LOOK,
	TOGGLE_UI,
}

Editor :: struct {
	ren:             ^Renderer,
	win:             ^Window,
	input:           ^Input,
	res:             ^Resources,
	scene:           ^Scene,
	physics:         ^Physics,
	cam:             Entity,
	selected_entity: Handle,
	controls:        [len(Editor_Actions)]Input_Action,
	fps:             f32,
	time_accum:      f32,
	frame_time:      f32,
	frame_count:     u32,
	cam_pitch:       f32,
	cam_yaw:         f32,
	move_speed:      f32,
	look_sens:       f32,
	hovering:        bool,
	ui_active:       bool,
}

get_c_string :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}

update_camera :: proc(editor: ^Editor) {
	profile_scoped()
	ren := editor.ren
	input := editor.input
	cam := &editor.cam.camera
	t := &editor.cam.transform
	look := &editor.controls[Editor_Actions.LOOK]
	move := &editor.controls[Editor_Actions.MOVEMENT]
	m1 := &editor.controls[Editor_Actions.M1]

	if m1.state < .ENDED {
		input.lock_mouse(editor.win.sdl_win, true)

		editor.cam_yaw += look.value.x * editor.look_sens
		editor.cam_pitch += look.value.y * editor.look_sens
		rot: [3]f32 = {editor.cam_pitch, editor.cam_yaw, 0.0}


		forward := get_forward(t)
		right := get_right(t)
		move_dir := (forward * move.value.y) + (right * move.value.x)
		new_pos := t.pos + move_dir * editor.move_speed * f32(editor.win.delta_time)

		set_euler_angles(t, rot)
		set_position(t, new_pos)
	} else if editor.controls[Editor_Actions.M1].state == Action_State.ENDED {
		input.lock_mouse(editor.win.sdl_win, false)
	}

	update_transform_matrices(&editor.cam, nil)

	cam.view = linalg.matrix4_inverse(t.world_transform)
	cam.proj = linalg.matrix4_perspective_f32(
		linalg.to_radians(cam.fov),
		cam.aspect,
		cam.near,
		cam.far,
		false,
	)

	cam.proj[1][1] *= -1.0
}

editor_draw_settings :: proc(editor: ^Editor) {
	scene := editor.scene

	imgui.Begin("Settings")
	defer imgui.End()


	imgui.DragFloat3("cam pos", &editor.cam.transform.pos, 0.01, 0.0, 0.0, "%.2f", {.ColorMarkers})

	if editor.time_accum >= 1.0 {
		editor.fps = f32(editor.frame_count) / editor.time_accum
		editor.frame_time = (editor.time_accum / f32(editor.frame_count)) * 1000.0
		editor.time_accum = 0.0
		editor.frame_count = 0
	} else {
		editor.time_accum += f32(editor.win.delta_time)
		editor.frame_count += 1
	}

	imgui.Checkbox("Enable CRT", &editor.ren.post_settings.crt_enabled)

	imgui.DragFloat2(
		"Pixel Size",
		&editor.ren.post_settings.pixel_size,
		3.0,
		3.0,
		0.0,
		"%.0f",
		{.ColorMarkers},
	)

	imgui.DragFloat2(
		"Pixel Fade",
		&editor.ren.post_settings.fade,
		0.001,
		0.0,
		1.0,
		"%.3f",
		{.ColorMarkers},
	)

	imgui.DragFloat3(
		"Min Pixel Brightness",
		(^[3]f32)(&editor.ren.post_settings.min_brightness),
		0.0001,
		0.0,
		2.0,
		"%.4f",
		{.ColorMarkers},
	)

	imgui.DragFloat3(
		"Light Direction",
		(^[3]f32)(&editor.ren.per_frame_uniform.light_dir),
		0.001,
		-1.0,
		1.0,
		"%.3f",
		{.ColorMarkers},
	)

	imgui.ColorEdit3("Color", (^[3]f32)(&editor.ren.per_frame_uniform.light_color), {})

	imgui.DragFloat(
		"Light Brightness",
		&editor.ren.per_frame_uniform.light_color.a,
		0.01,
		0.0,
		0.0,
		"%.2f",
		{.ColorMarkers},
	)

	imgui.DragFloat(
		"Ambient Brightness",
		&editor.ren.per_frame_uniform.ambient,
		0.01,
		0.0,
		1.0,
		"%.2f",
		{.ColorMarkers},
	)
	imgui.Text("FPS: %.2f", editor.fps)
	imgui.Text("Frame time: %.2f", editor.frame_time)
	imgui.Text("Entity count: %u", editor.scene.entities.items.len)

	if imgui.Button("Add Rigidbody") {

		for x in 0 ..< 4 {
			for y in 0 ..< 4 {
				for z in 0 ..< 4 {
					posx := u32(x) * 2
					posy := u32(y) * 2
					posz := u32(z) * 2
					eh, e := scene_get_new_entity(scene)
					set_position(&e.transform, {f32(posx), f32(posy + 30.0), f32(posz)})
					mr := entity_add_mesh(editor.scene, e, editor.ren, editor.res)
					mr.mesh = editor.res.mesh_map["cube.gltf"]
					mr.color = {0.0, 1.0, 0.0, 1.0}
					entity_add_rigidbody(editor.scene, editor.physics, e, .dynamicBody)
				}
			}
		}
	}

	if imgui.Button("Save Scene") {
		write_scene(editor.scene)
	}
}

cstring_from_buf :: proc(buf: []byte, str: string) -> cstring {
	sb := strings.builder_from_bytes(buf)
	strings.write_string(&sb, str)
	return strings.to_cstring(&sb)
}

editor_draw_inspector :: proc(editor: ^Editor) {
	scene := editor.scene
	imgui.Begin("Inspector")
	defer imgui.End()

	if hm.is_valid(&scene.entities, editor.selected_entity) {
		e := hm.get(&scene.entities, editor.selected_entity)

		if imgui.IsWindowHovered(0) && editor.controls[Editor_Actions.M1].state == .STARTED {
			imgui.OpenPopup("entityctx")
		}

		if imgui.BeginPopup("entityctx") {

			if imgui.MenuItem("Add Mesh Renderer", nil, false, .MESH_RENDERER not_in e.flags) {
				entity_add_mesh(editor.scene, e, editor.ren, editor.res)
			}

			if imgui.MenuItem("Add Rigidbody", nil, false, .RIGIDBODY not_in e.flags) {
				entity_add_rigidbody(editor.scene, editor.physics, e, .staticBody)
			}

			imgui.EndPopup()
		}

		buf: [256]byte

		name := cstring_from_buf(buf[:], e.name)
		if imgui.InputText("##", name, len(buf)) {
			delete(e.name)
			e.name = strings.clone_from_cstring(cstring(&buf[0]))
		}

		if imgui.CollapsingHeader("Transform", {.DefaultOpen, .DrawLinesFull}) {
			t := &e.transform
			if imgui.DragFloat3("Pos", &t.pos, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_position(t, t.pos)
			if imgui.DragFloat3("Rot", &t.euler_angles, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_euler_angles(t, t.euler_angles)
			if imgui.DragFloat3("Scale", &t.scale, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_scale(t, t.scale)

			parent_name: string = "none"

			if hm.is_valid(&scene.entities, e.parent) {
				p := hm.get(&scene.entities, e.parent)
				parent_name = p.name
			}

			if imgui.BeginCombo("Parent", get_c_string(parent_name), {}) {
				it := hm.iterator_make(&scene.entities)
				for ent, h in hm.iterate(&it) {
					if ent != e {
						imgui.PushIDPtr(ent)
						if (imgui.Selectable(get_c_string(ent.name))) {
							e.parent = h
							append(&ent.children, editor.selected_entity)
						}
						imgui.PopID()
					}
				}
				imgui.EndCombo()
			}
		}

		if .MESH_RENDERER in e.flags {
			mr := &e.mesh_renderer

			if imgui.CollapsingHeader("Mesh Renderer", {.DefaultOpen, .DrawLinesFull}) {

				if imgui.BeginCombo("Mesh", get_c_string(mr.mesh.name), {}) {
					meshes := &editor.res.mesh_map

					for k, &v in meshes {
						if imgui.Selectable(get_c_string(mr.mesh.name)) {
							mr.mesh = v
						}
					}

					imgui.EndCombo()
				}

				imgui.ColorEdit4("Color", &mr.color, {})

			}
		}

		if .RIGIDBODY in e.flags {
			rb := &e.rigidbody

			if imgui.CollapsingHeader("Rigidbody", {.DefaultOpen, .DrawLinesFull}) {

				type_str: cstring = "static"

				type := b3.Body_GetType(rb.body_id)

				if type == .kinematicBody {
					type_str = "kinematic"
				} else if type == .dynamicBody {
					type_str = "dynamic"
				}


				if imgui.BeginCombo("Type", type_str, {}) {

					if type != .staticBody {
						if imgui.Selectable("static") {
							b3.Body_SetType(rb.body_id, .staticBody)
						}
					}

					if type != .kinematicBody {
						if imgui.Selectable("kinematic") {
							b3.Body_SetType(rb.body_id, .kinematicBody)
						}
					}


					if type != .dynamicBody {
						if imgui.Selectable("dynamic") {
							b3.Body_SetType(rb.body_id, .dynamicBody)
						}
					}
					imgui.EndCombo()
				}


			}
		}
	}
}

editor_draw_entities :: proc(editor: ^Editor) {
	imgui.Begin("Entities")
	defer imgui.End()


	s := editor.scene
	entities := &s.entities

	if imgui.Button(" + ", {imgui.GetContentRegionAvail().x, 0.0}) {
		scene_get_new_entity(s)
	}

	imgui.NewLine()

	if imgui.IsWindowHovered() && editor.input.m0 do editor.selected_entity = {}

	it := hm.iterator_make(&s.entities)

	for e, h in hm.iterate(&it) {
		imgui.PushIDPtr(e)
		selected := editor.selected_entity == h
		if imgui.Selectable(get_c_string(e.name), selected, {}) do editor.selected_entity = h
		imgui.PopID()
	}
}

editor_check_pick :: proc(editor: ^Editor) {
	if editor.controls[Editor_Actions.M0].state == .ENDED {
		if editor.ren.picking_hits.hit_count != 0 {
			editor.ren.selected_entity = editor.ren.picking_hits.hits[0].handle
			editor.selected_entity = editor.ren.selected_entity
		}
	}
}


editor_update :: proc(editor: ^Editor) {
	profile_scoped()
	update_controls(editor.controls[:])
	update_camera(editor)

	if editor.controls[Editor_Actions.TOGGLE_UI].state == .STARTED do editor.ui_active = !editor.ui_active

	if !editor.hovering {
		editor_check_pick(editor)
	}

	editor.hovering = false

	imgui_impl_sdl3.NewFrame()
	imgui_impl_vulkan.NewFrame()
	imgui.NewFrame()
	// imgui.DockSpaceOverViewport(0, imgui.GetMainViewport(), {.PassthruCentralNode}, nil)

	if editor.ui_active {
		editor_draw_settings(editor)
		editor_draw_entities(editor)
		editor_draw_inspector(editor)
	}

	if imgui.IsWindowHovered(
		imgui.HoveredFlags(
			imgui.HoveredFlags_AnyWindow |
			imgui.HoveredFlags_AllowWhenBlockedByActiveItem |
			imgui.HoveredFlags_ChildWindows,
		),
	) {
		editor.hovering = true
	}


	imgui.Render()
}

imgui_init :: proc(editor: ^Editor) {
	ctx := imgui.CreateContext()
	imgui.SetCurrentContext(ctx)
	io := imgui.GetIO()

	io.ConfigFlags += {.DockingEnable}
	imgui_impl_sdl3.InitForVulkan(editor.win.sdl_win)
	fmt := editor.ren.swap_format

	pri: vk.PipelineRenderingCreateInfo = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &fmt,
		depthAttachmentFormat   = editor.ren.depth_format,
	}

	pi: imgui_impl_vulkan.PipelineInfo = {
		MSAASamples                 = {._1},
		PipelineRenderingCreateInfo = pri,
	}

	init_info: imgui_impl_vulkan.InitInfo = {
		Instance            = editor.ren.instance,
		PhysicalDevice      = editor.ren.physical,
		Device              = editor.ren.device,
		QueueFamily         = editor.ren.gfx_q_family,
		Queue               = editor.ren.gfx_q,
		DescriptorPoolSize  = 100,
		UseDynamicRendering = true,
		PipelineInfoMain    = pi,
		MinImageCount       = 2,
		ImageCount          = 2,
	}

	imgui_impl_vulkan.LoadFunctions(vk.API_VERSION_1_4, imgui_vulkan_callback, rawptr(editor))
	imgui_impl_vulkan.Init(&init_info)
}

imgui_vulkan_callback :: proc "c" (
	function_name: cstring,
	user_data: rawptr,
) -> vk.ProcVoidFunction {
	editor := (^Editor)(user_data)
	ren := editor.ren

	if func := vk.GetInstanceProcAddr(ren.instance, function_name); func != nil {
		return func
	}

	if func := vk.GetDeviceProcAddr(ren.device, function_name); func != nil {
		return func
	}

	return nil
}

editor_init :: proc(
	editor: ^Editor,
	win: ^Window,
	input: ^Input,
	ren: ^Renderer,
	res: ^Resources,
	phys: ^Physics,
	scene: ^Scene,
) {
	editor.win = win
	editor.input = input
	editor.ren = ren
	editor.res = res
	editor.physics = phys
	editor.scene = scene

	editor.cam.transform.world_transform = linalg.MATRIX4F32_IDENTITY
	editor.cam.transform.pos = {0.0, 15.0, -10.0}
	editor.cam.transform.rot = linalg.QUATERNIONF32_IDENTITY
	editor.cam.transform.scale = {1.0, 1.0, 1.0}
	// editor.cam.transform.entity = &editor.cam
	cam := &editor.cam.camera
	cam.aspect = 800.0 / 600.0
	cam.fov = 78.0
	cam.near = 0.1
	cam.far = 10000

	editor.look_sens = 0.08
	editor.move_speed = 8.0

	editor.controls[Editor_Actions.MOVEMENT].control = Control_Axis2 {
		x = {
			negative = &input.sdl_keys[sdl.Scancode.A],
			positive = &input.sdl_keys[sdl.Scancode.D],
		},
		y = {
			negative = &input.sdl_keys[sdl.Scancode.S],
			positive = &input.sdl_keys[sdl.Scancode.W],
		},
	}

	editor.controls[Editor_Actions.LOOK].control = Control_Pointer {
		x = &input.mouse_delta.x,
		y = &input.mouse_delta.y,
	}

	editor.controls[Editor_Actions.M0].control = &input.m0
	editor.controls[Editor_Actions.M1].control = &input.m1
	editor.controls[Editor_Actions.TOGGLE_UI].control = &input.sdl_keys[sdl.Scancode.F1]

	imgui_init(editor)
}
