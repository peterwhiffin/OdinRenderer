package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_sdl3"
import "../../odin-imgui/imgui_impl_vulkan"
import hm "core:container/handle_map"
import "core:crypto/poly1305"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:slice"
import "core:strings"
import b3 "vendor:box3d"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

Editor_Actions :: enum {
	Movement,
	M0,
	M1,
	Shift,
	Look,
	Toggle_UI,
	Play,
}

Editor_Mode :: enum {
	Normal,
	Camera,
	Play,
}


Editor :: struct {
	ren:               ^Renderer,
	win:               ^Window,
	input:             ^Input,
	res:               ^Resources,
	scene:             ^Scene,
	physics:           ^Physics,
	game:              ^Game,
	cam:               Handle,
	gizmo_scene:       Scene,
	transform_gizmo:   Handle,
	x_gizmo:           Handle,
	y_gizmo:           Handle,
	z_gizmo:           Handle,
	selected_entity:   Handle,
	selected_gizmo:    Handle,
	controls:          [len(Editor_Actions)]Input_Action,
	initial_hit_axis:  f32,
	original_drag_pos: [3]f32,
	transform_speed:   f32,
	fps:               f32,
	time_accum:        f32,
	frame_time:        f32,
	frame_count:       u32,
	cam_pitch:         f32,
	cam_yaw:           f32,
	move_speed:        f32,
	look_sens:         f32,
	gizmo_scale:       f32,
	hovering_ui:       bool,
	ui_active:         bool,
	mode:              Editor_Mode,
}

get_c_string :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}

editor_move_camera :: proc(editor: ^Editor) {
	profile_scoped()
	ren := editor.ren
	input := editor.input
	cam_e := hm.get(&editor.gizmo_scene.entities, editor.cam)
	cam := &cam_e.camera
	t := &cam_e.transform
	look := &editor.controls[Editor_Actions.Look]
	move := &editor.controls[Editor_Actions.Movement]
	m1 := &editor.controls[Editor_Actions.M1]


	editor.cam_yaw += look.value.x * editor.look_sens
	editor.cam_pitch += look.value.y * editor.look_sens
	rot: [3]f32 = {editor.cam_pitch, editor.cam_yaw, 0.0}


	forward := get_forward(t)
	right := get_right(t)
	move_dir := (forward * move.value.y) + (right * move.value.x)
	new_pos := t.pos + move_dir * editor.move_speed * f32(editor.win.delta_time)

	set_euler_angles(t, rot, editor.scene)
	set_position(t, new_pos, editor.scene)


	// update_transform_matrices(&editor.cam, nil)

	cam.view = la.matrix4_inverse(t.world_transform)
	cam.proj = la.matrix4_perspective_f32(
		la.to_radians(cam.fov),
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


	// imgui.DragFloat3("cam pos", &editor.cam.transform.pos, 0.01, 0.0, 0.0, "%.2f", {.ColorMarkers})

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

	imgui.DragFloat(
		"Player Jump Height",
		&editor.game.player.jump_height,
		0.01,
		0.0,
		1000.0,
		"%.2f",
		{.ColorMarkers},
	)

	imgui.DragFloat(
		"Transform Speed",
		&editor.transform_speed,
		0.00001,
		0.0,
		1000.0,
		"%.5f",
		{.ColorMarkers},
	)

	imgui.DragFloat("Gizmo Scale", &editor.gizmo_scale, 0.001, 0.0, 10.0, "%.3f", {.ColorMarkers})

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
					set_position(
						&e.transform,
						{f32(posx), f32(posy + 30.0), f32(posz)},
						editor.scene,
					)
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

	tex_ref: imgui.TextureRef = {
		_TexID = 8,
	}

	// imgui.Image(tex_ref, {100, 100})
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

	if e, ok := hm.get(&scene.entities, editor.selected_entity); ok {
		if imgui.IsWindowHovered(0) && editor.controls[Editor_Actions.M1].state == .Started {
			imgui.OpenPopup("entityctx")
		}

		if imgui.BeginPopup("entityctx") {

			if imgui.MenuItem("Add Mesh Renderer", nil, false, .Mesh_Renderer not_in e.flags) {
				entity_add_mesh(editor.scene, e, editor.ren, editor.res)
			}

			if imgui.MenuItem("Add Rigidbody", nil, false, .Rigidbody not_in e.flags) {
				entity_add_rigidbody(editor.scene, editor.physics, e, .staticBody)
			}

			imgui.EndPopup()
		}

		buf: [256]byte
		name := cstring_from_buf(buf[:], e.name)

		if imgui.InputText("##", name, len(buf)) {
			// delete(e.name)
			e.name = strings.clone_from_cstring(cstring(&buf[0]))
		}

		if imgui.CollapsingHeader("Transform", {.DefaultOpen, .DrawLinesFull}) {
			t := &e.transform
			if imgui.DragFloat3("Pos", &t.pos, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_position(t, t.pos, editor.scene)
			if imgui.DragFloat3("Rot", &t.euler_angles, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_euler_angles(t, t.euler_angles, editor.scene)
			if imgui.DragFloat3("Scale", &t.scale, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers}) do set_scale(t, t.scale, editor.scene)

			parent_name: string = "none"

			if p, ok := hm.get(&scene.entities, e.parent); ok {
				parent_name = p.name
			}

			if imgui.BeginCombo("Parent", get_c_string(parent_name), {}) {
				it := hm.iterator_make(&scene.entities)
				for ent, h in hm.iterate(&it) {
					if ent != e {
						imgui.PushIDPtr(ent)
						if (imgui.Selectable(get_c_string(ent.name))) {
							// e.parent = h
							// append(&ent.children, editor.selected_entity)
							set_parent(e.handle, h, editor.scene)
						}
						imgui.PopID()
					}
				}
				imgui.EndCombo()
			}
		}

		if .Mesh_Renderer in e.flags {
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

		if .Rigidbody in e.flags {
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
	if editor.controls[Editor_Actions.M0].state == .Started {
		if editor.ren.picker.hit_count != 0 {
			for i in 0 ..< editor.ren.picker.hit_count {
				hit := editor.ren.picker.hits[i].handle

				if hit == editor.x_gizmo {
					editor.selected_gizmo = editor.x_gizmo
				} else if hit == editor.y_gizmo {

				} else if hit == editor.z_gizmo {
				} else if hit == editor.x_gizmo {

				} else if hit == editor.transform_gizmo {

				} else {
					editor.ren.selected_entity = editor.ren.picker.hits[0].handle
					editor.selected_entity = editor.ren.selected_entity
				}
			}

		}
	}
}

intersect_ray_plane :: proc(n: [3]f32, p0: [3]f32, l0: [3]f32, l: [3]f32) -> ([3]f32, bool) {
	//plane is described by point p0, which is it's world space position/origin
	//and a normal N, the planes orientation. The normal of the world xy plane would be the world z axis
	//you can derive a vector on the plane from any point(p) by subtracting p0 from p
	//
	//dot product of two perpendicular vectors is 0
	// (p - p0) dot n = 0
	//
	// ray is an origin and a direction, and we will use a scalar t to define magnitude/distance
	// l0 is ray origin. l is ray direction. t is scalar
	// l0 + l * t = p
	//
	// if the ray intersects the plane, they share a point(p) at the intersection.
	// substitue ray equation.
	// (l0 + l * t - p0) dot n = 0
	//
	// we want to find a t that results in an intersection
	// t = ((p0 - l0) dot n) / (l dot n)
	//
	// when l dot n approaches 0(ray direction and plane normal are perpendicular), the plane is parallel with the ray.
	// we need an epsilon to prevent dividing by zero
	//
	// vectors need to be normalized

	intersects := false
	hit_point: [3]f32
	epsilon: f32 = 1e-6
	t: f32

	denom := la.dot(n, l)

	// abs to account for rays approaching from either side of the plane
	if (la.abs(denom) > epsilon) {
		p0_l0 := p0 - l0
		t = la.dot(p0_l0, n) / denom
		intersects = t >= 0
		hit_point = l0 + l * t
	}

	return hit_point, intersects
}

screen_to_ray :: proc(cam: ^Camera, screen_pos: [2]f32, scene: ^Scene, win: ^Window) -> [3]f32 {
	ce := entity_get(cam.entity, scene)
	norm := screen_pos / {f32(win.w), f32(win.h)}
	ndc := norm * 2.0 - 1.0
	clip: [4]f32 = {ndc.x, ndc.y, -1.0, 1.0}
	view := la.matrix4_inverse(ce.camera.proj) * clip
	view = {view.x, view.y, -1.0, 0.0}
	ray_dir := la.matrix4_inverse(ce.camera.view) * view
	return la.normalize(ray_dir.xyz)
}

editor_update_normal :: proc(editor: ^Editor) {

	// se := entity_get(editor.selected_entity, editor.scene)

	hover_flags := imgui.HoveredFlags(
		imgui.HoveredFlags_AnyWindow |
		imgui.HoveredFlags_AllowWhenBlockedByActiveItem |
		imgui.HoveredFlags_ChildWindows,
	)

	editor.hovering_ui = imgui.IsWindowHovered(hover_flags)

	if !editor.hovering_ui {
		editor_check_pick(editor)
		if editor.controls[Editor_Actions.M1].state == .Started {
			editor.mode = .Camera
			editor.input.lock_mouse(editor.win.sdl_win, true)
		}


		if editor.selected_gizmo == editor.x_gizmo {
			if editor.controls[Editor_Actions.M0].state < .Ended {
				se := entity_get(editor.selected_entity, editor.scene)
				ce := entity_get(editor.cam, &editor.gizmo_scene)

				if editor.controls[Editor_Actions.M0].state == .Started {
					editor.original_drag_pos = se.transform.pos

					ray := screen_to_ray(
						&ce.camera,
						editor.input.relative_mouse_pos,
						&editor.gizmo_scene,
						editor.win,
					)

					hit, ok := intersect_ray_plane(
						{0.0, 0.0, 1.0},
						se.transform.pos,
						ce.transform.pos,
						ray,
					)

					editor.initial_hit_axis = la.dot(hit - se.transform.pos, [3]f32{1.0, 0.0, 0.0})
					fmt.println("Setting initial hit")
				} else {

					ray := screen_to_ray(
						&ce.camera,
						editor.input.relative_mouse_pos,
						&editor.gizmo_scene,
						editor.win,
					)
					hit, ok := intersect_ray_plane(
						{0.0, 0.0, 1.0},
						editor.original_drag_pos,
						ce.transform.pos,
						ray,
					)

					current_hit_axis := la.dot(
						hit - editor.original_drag_pos,
						[3]f32{1.0, 0.0, 0.0},
					)
					// delta := current_hit_axis - editor.initial_hit_axis
					delta := editor.initial_hit_axis - current_hit_axis
					set_position(
						&se.transform,
						editor.original_drag_pos + [3]f32{1.0, 0.0, 0.0} * delta,
						editor.scene,
					)

				}


			} else {
				editor.selected_gizmo = {}
			}
		}


	}

	if editor.controls[Editor_Actions.Play].state == .Started {
		editor.mode = .Play
		editor.input.lock_mouse(editor.win.sdl_win, true)

	}
}

editor_update_camera :: proc(editor: ^Editor) {
	editor_move_camera(editor)

	if editor.controls[Editor_Actions.M1].state == .Ended {
		editor.mode = .Normal
		editor.input.lock_mouse(editor.win.sdl_win, false)
	} else if editor.controls[Editor_Actions.Play].state == .Started {
		editor.mode = .Play
		editor.input.lock_mouse(editor.win.sdl_win, true)
	}
}

editor_draw :: proc(editor: ^Editor) {
	imgui_impl_sdl3.NewFrame()
	imgui_impl_vulkan.NewFrame()
	imgui.NewFrame()
	// imgui.DockSpaceOverViewport(0, imgui.GetMainViewport(), {.PassthruCentralNode}, nil)

	if editor.ui_active {
		editor_draw_settings(editor)
		editor_draw_entities(editor)
		editor_draw_inspector(editor)
	}

	imgui.Render()
}

editor_update_play :: proc(editor: ^Editor) {
	if editor.controls[Editor_Actions.Play].state == .Started {
		editor.mode = .Normal
		editor.input.lock_mouse(editor.win.sdl_win, false)
	}

	// editor_move_player(editor)

	game_update(editor.game, editor.scene, editor.input)
}

editor_update_gizmo :: proc(editor: ^Editor) {
	if editor.selected_entity != {} {
		gizmo_e := hm.get(&editor.gizmo_scene.entities, editor.transform_gizmo)
		selected_e := hm.get(&editor.scene.entities, editor.selected_entity)
		set_position(&gizmo_e.transform, selected_e.transform.pos, &editor.gizmo_scene)
		set_rotation(&gizmo_e.transform, selected_e.transform.rot, &editor.gizmo_scene)
	}


	ce := entity_get(editor.cam, &editor.gizmo_scene)
	ge := entity_get(editor.transform_gizmo, &editor.gizmo_scene)

	dist := la.distance(ce.transform.pos, ge.transform.pos)

	set_scale(&ge.transform, dist * editor.gizmo_scale, &editor.gizmo_scene)
}

editor_update :: proc(editor: ^Editor) -> ^Camera {
	profile_scoped()
	cam_e := hm.get(&editor.gizmo_scene.entities, editor.cam)
	cam := &cam_e.camera

	input_update_controls(editor.controls[:])
	if editor.controls[Editor_Actions.Toggle_UI].state == .Started do editor.ui_active = !editor.ui_active

	switch editor.mode {
	case .Normal:
		editor_update_normal(editor)
		editor_update_gizmo(editor)
	case .Camera:
		editor_update_camera(editor)
		editor_update_gizmo(editor)
	case .Play:
		editor_update_play(editor)
		ce := hm.get(&editor.scene.entities, editor.game.main_camera)
		cam = &ce.camera
	}

	scene_update_transforms(&editor.gizmo_scene)
	editor_draw(editor)


	return cam
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

	as_u32v := slice.reinterpret([]u32, SHADER_IMGUI_VERT)
	as_u32f := slice.reinterpret([]u32, SHADER_IMGUI_FRAG)

	mciv: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(SHADER_IMGUI_VERT),
		pCode    = raw_data(as_u32v),
	}

	mcif: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(SHADER_IMGUI_FRAG),
		pCode    = raw_data(as_u32f),
	}

	init_info: imgui_impl_vulkan.InitInfo = {
		Instance                   = editor.ren.instance,
		PhysicalDevice             = editor.ren.physical,
		Device                     = editor.ren.device,
		QueueFamily                = editor.ren.gfx_q_family,
		Queue                      = editor.ren.gfx_q,
		DescriptorPoolSize         = 100,
		UseDynamicRendering        = true,
		PipelineInfoMain           = pi,
		MinImageCount              = 2,
		ImageCount                 = 2,
		CustomShaderVertCreateInfo = mciv,
		CustomShaderFragCreateInfo = mcif,
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

editor_init_gizmos :: proc(editor: ^Editor) {
	// tcenter_h, tcenter_e := scene_get_new_entity(editor.scene)
	// tx_h, tx_e := scene_get_new_entity(editor.scene)
	// ty_h, ty_e := scene_get_new_entity(editor.scene)
	// tz_h, tz_e := scene_get_new_entity(editor.scene)
	//
	// tmrc := entity_add_mesh(editor.scene, tcenter_e, editor.ren, editor.res)
	// tmrx := entity_add_mesh(editor.scene, tx_e, editor.ren, editor.res)
	// tmry := entity_add_mesh(editor.scene, ty_e, editor.ren, editor.res)
	// tmrz := entity_add_mesh(editor.scene, tz_e, editor.ren, editor.res)
	//
	// tmrc.color = {0.3, 0.3, 0.3, 1.0}
	// tmrx.color = {1.0, 0.0, 0.0, 1.0}
	// tmry.color = {0.0, 1.0, 0.0, 1.0}
	// tmrz.color = {0.0, 0.0, 1.0, 1.0}
	//
	// tlength: f32 = 3.0
	// twidth: f32 = 0.1
	//
	//
	// toffset := tlength
	//
	//
	// set_position(&tx_e.transform, {toffset, 0.0, 0.0}, editor.scene)
	// set_position(&ty_e.transform, {0.0, toffset, 0.0}, editor.scene)
	// set_position(&tz_e.transform, {0.0, 0.0, toffset}, editor.scene)
	//
	// set_scale(&tcenter_e.transform, {0.15, 0.15, 0.15}, editor.scene)
	// set_scale(&tx_e.transform, {tlength, twidth, twidth}, editor.scene)
	// set_scale(&ty_e.transform, {twidth, tlength, twidth}, editor.scene)
	// set_scale(&tz_e.transform, {twidth, twidth, tlength}, editor.scene)
	//
	//
	// set_parent(tx_h, tcenter_h, editor.scene)
	// set_parent(ty_h, tcenter_h, editor.scene)
	// set_parent(tz_h, tcenter_h, editor.scene)
	// set_position(&tcenter_e.transform, {0.0, 10.0, 0.0}, editor.scene)
	//
	//
	//
	//

	center_h, center_e := scene_get_new_entity(&editor.gizmo_scene)
	x_h, x_e := scene_get_new_entity(&editor.gizmo_scene)
	y_h, y_e := scene_get_new_entity(&editor.gizmo_scene)
	z_h, z_e := scene_get_new_entity(&editor.gizmo_scene)

	editor.transform_gizmo = center_h
	editor.x_gizmo = x_h
	editor.y_gizmo = y_h
	editor.z_gizmo = z_h

	mrc := entity_add_mesh(&editor.gizmo_scene, center_e, editor.ren, editor.res)
	mrx := entity_add_mesh(&editor.gizmo_scene, x_e, editor.ren, editor.res)
	mry := entity_add_mesh(&editor.gizmo_scene, y_e, editor.ren, editor.res)
	mrz := entity_add_mesh(&editor.gizmo_scene, z_e, editor.ren, editor.res)

	mrc.color = {0.3, 0.3, 0.3, 1.0}
	mrx.color = {1.0, 0.0, 0.0, 1.0}
	mry.color = {0.0, 1.0, 0.0, 1.0}
	mrz.color = {0.0, 0.0, 1.0, 1.0}

	length: f32 = 3.0
	width: f32 = 0.1


	offset := length


	set_position(&x_e.transform, {offset, 0.0, 0.0}, &editor.gizmo_scene)
	set_position(&y_e.transform, {0.0, offset, 0.0}, &editor.gizmo_scene)
	set_position(&z_e.transform, {0.0, 0.0, offset}, &editor.gizmo_scene)

	set_scale(&center_e.transform, {0.15, 0.15, 0.15}, &editor.gizmo_scene)
	set_scale(&x_e.transform, {length, width, width}, &editor.gizmo_scene)
	set_scale(&y_e.transform, {width, length, width}, &editor.gizmo_scene)
	set_scale(&z_e.transform, {width, width, length}, &editor.gizmo_scene)


	set_parent(x_h, center_h, &editor.gizmo_scene)
	set_parent(y_h, center_h, &editor.gizmo_scene)
	set_parent(z_h, center_h, &editor.gizmo_scene)
	//
	set_position(&center_e.transform, {0.0, 10.0, 0.0}, &editor.gizmo_scene)
}

editor_init :: proc(
	editor: ^Editor,
	win: ^Window,
	input: ^Input,
	ren: ^Renderer,
	res: ^Resources,
	phys: ^Physics,
	scene: ^Scene,
	game: ^Game,
) {
	editor.win = win
	editor.input = input
	editor.ren = ren
	editor.res = res
	editor.physics = phys
	editor.scene = scene
	editor.game = game

	scene_init(&editor.gizmo_scene)

	cam_e: ^Entity
	editor.cam, cam_e = scene_get_new_entity(&editor.gizmo_scene)
	entity_add_camera(cam_e, editor.win)
	set_position(&cam_e.transform, {0.0, 20.0, -10.0}, &editor.gizmo_scene)


	// cam := &editor.cam.camera
	// cam.aspect = 800.0 / 600.0
	// cam.fov = 78.0
	// cam.near = 0.1
	// cam.far = 10000

	editor.look_sens = 0.08
	editor.move_speed = 8.0
	// editor.play_move_speed = 5.0

	editor.controls[Editor_Actions.Movement].control = Control_Axis2 {
		x = {
			negative = &input.sdl_keys[sdl.Scancode.A],
			positive = &input.sdl_keys[sdl.Scancode.D],
		},
		y = {
			negative = &input.sdl_keys[sdl.Scancode.S],
			positive = &input.sdl_keys[sdl.Scancode.W],
		},
	}

	editor.controls[Editor_Actions.Look].control = Control_Pointer {
		x = &input.mouse_delta.x,
		y = &input.mouse_delta.y,
	}

	editor.controls[Editor_Actions.M0].control = &input.m0
	editor.controls[Editor_Actions.M1].control = &input.m1
	editor.controls[Editor_Actions.Toggle_UI].control = &input.sdl_keys[sdl.Scancode.F1]
	editor.controls[Editor_Actions.Play].control = &input.sdl_keys[sdl.Scancode.F2]

	editor.mode = .Camera
	editor.gizmo_scale = 0.01

	editor_init_gizmos(editor)
	imgui_init(editor)
}
