package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_sdl3"
import "../../odin-imgui/imgui_impl_vulkan"
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import b3 "vendor:box3d"
import vk "vendor:vulkan"

Editor :: struct {
	ren:        ^Renderer,
	win:        ^Window,
	input:      ^Input,
	res:        ^Resources,
	scene:      ^Scene,
	physics:    ^Physics,
	cam:        Entity,
	selected:   ^Entity,
	cam_pitch:  f32,
	cam_yaw:    f32,
	move_speed: f32,
	look_sens:  f32,
}

update_camera :: proc(editor: ^Editor) {
	ren := editor.ren
	input := editor.input
	cam := &editor.cam.camera
	t := &editor.cam.transform

	if input.m1 {
		input.lock_mouse(editor.win.sdl_win, true)
	} else {
		input.lock_mouse(editor.win.sdl_win, false)
	}

	if input.m1 {
		editor.cam_yaw += input.mouse_delta.x * editor.look_sens
		editor.cam_pitch += input.mouse_delta.y * editor.look_sens

		rot: [3]f32 = {editor.cam_pitch, editor.cam_yaw, 0.0}

		// set_rotation(t, rot)
		set_euler_angles(t, rot)

		forward := get_forward(t)
		right := get_right(t)

		move_dir := (forward * input.wasd.y) + (right * input.wasd.x)

		new_pos := t.pos + move_dir * editor.move_speed * f32(editor.win.delta_time)

		set_position(t, new_pos)
	}

	update_transform_matrices(&editor.cam.transform)

	eye: linalg.Vector3f32 = t.pos
	center: linalg.Vector3f32 = eye + get_forward(t)
	up: linalg.Vector3f32 = get_up(t)

	// cam.view = linalg.matrix4_look_at(eye, center, up)
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
	imgui.Begin("Settings")
	defer imgui.End()

	imgui.DragFloat3("cam pos", &editor.cam.transform.pos, 0.01, 0.0, 0.0, "%.2f", {.ColorMarkers})
}

editor_draw_inspector :: proc(editor: ^Editor) {
	imgui.Begin("Inspector")
	defer imgui.End()

	if editor.selected != nil {
		e := editor.selected

		if imgui.IsWindowHovered(0) && editor.input.m1 {
			imgui.OpenPopup("entityctx")
		}

		if imgui.BeginPopup("entityctx") {

			if imgui.MenuItem("Add Mesh Renderer", nil, false, .MESH_RENDERER not_in e.flags) {
				entity_add_mesh(editor.scene, e, editor.ren, editor.res)
			}

			if imgui.MenuItem("Add Rigidbody", nil, false, .RIGIDBODY not_in e.flags) {
				entity_add_rigidbody(editor.scene, editor.physics, e)
			}

			imgui.EndPopup()
		}

		if imgui.CollapsingHeader("Transform", {.DefaultOpen, .DrawLinesFull}) {
			t := &e.transform
			imgui.DragFloat3("Pos", &t.pos, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers})
			imgui.DragFloat3("Rot", &t.euler_angles, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers})
			imgui.DragFloat3("Scale", &t.scale, 0.01, 0.0, 0.0, "%.3f", {.ColorMarkers})

			set_position(t, t.pos)
			set_euler_angles(t, t.euler_angles)
			set_scale(t, t.scale)

			parent_name: cstring = "none"
			if e.transform.parent != nil {
				parent_name = e.transform.parent.entity.name
			}

			if imgui.BeginCombo("Parent", parent_name, {}) {
				for i in 0 ..< editor.scene.entities.count {
					ent := &editor.scene.entities.data[i]
					if ent != e {
						imgui.PushIDPtr(ent)
						if (imgui.Selectable(ent.name)) {
							e.transform.parent = &ent.transform
							append(&ent.transform.children, &e.transform)
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

				if imgui.BeginCombo("Mesh", mr.mesh.name, {}) {
					meshes := &editor.res.meshes
					for i in 0 ..< meshes.count {
						if imgui.Selectable(meshes.data[i].name) {
							mr.mesh = &meshes.data[i]
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

	if imgui.IsWindowHovered() && editor.input.m0 do editor.selected = nil

	for i in 0 ..< s.entities.count {
		e := &s.entities.data[i]
		imgui.PushIDPtr(e)
		selected := editor.selected == e
		if imgui.Selectable(e.name, selected, {}) do editor.selected = e
		imgui.PopID()
	}
}


editor_update :: proc(editor: ^Editor) {
	update_camera(editor)

	show_demo: bool = true

	imgui_impl_sdl3.NewFrame()
	imgui_impl_vulkan.NewFrame()
	imgui.NewFrame()
	imgui.DockSpaceOverViewport(0, imgui.GetMainViewport(), {.PassthruCentralNode}, nil)

	imgui.ShowDemoWindow(&show_demo)
	editor_draw_settings(editor)
	editor_draw_entities(editor)
	editor_draw_inspector(editor)
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
	// vk.load_proc_addresses_global(rawptr(sdl.Vulkan_GetVkGetInstanceProcAddr()))
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
	cam := &editor.cam.camera
	cam.aspect = 800.0 / 600.0
	cam.fov = 78.0
	cam.near = 0.1
	cam.far = 10000

	editor.look_sens = 0.08
	editor.move_speed = 8.0

	imgui_init(editor)
}
