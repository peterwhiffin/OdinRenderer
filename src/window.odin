package main

import "../../odin-imgui/imgui_impl_sdl3"
import "core:c"
import hm "core:container/handle_map"

import sdl "vendor:sdl3"

Window :: struct {
	input:          ^Input,
	sdl_win:        ^sdl.Window,
	frame_start:    u64,
	last_time:      u64,
	target_time:    u64,
	elapsed_time:   u64,
	spin_threshold: u64,
	delta_time:     f64,
	target_fps:     u32,
	w:              u32,
	h:              u32,
	should_close:   bool,
}

Input :: struct {
	lock_mouse:         proc "c" (window: ^sdl.Window, enabled: bool) -> bool,
	sdl_keys:           [^]bool,
	mouse_delta:        [2]f32,
	relative_mouse_pos: [2]f32,
	m0:                 bool,
	m1:                 bool,
}

Control_Bool :: ^bool

Control_Axis :: struct {
	positive: ^bool,
	negative: ^bool,
}

Control_Axis2 :: struct {
	x: Control_Axis,
	y: Control_Axis,
}

Control_Pointer :: struct {
	x: ^f32,
	y: ^f32,
}

Control :: union {
	Control_Bool,
	Control_Axis,
	Control_Axis2,
	Control_Pointer,
}

Action_State :: enum {
	Started,
	Performing,
	Ended,
	Sleeping,
}

Input_Action :: struct {
	control:  Control,
	value:    [2]f32,
	state:    Action_State,
	callback: proc(action: Input_Action),
}


read_value_button :: proc(b: Control_Bool) -> (value: f32, active: bool) {
	if value := b^ ? 1.0 : 0.0; value != 0 {
		active = true
	}

	return value, active
}

read_value_axis :: proc(b: Control_Axis) -> (value: f32, active: bool) {
	ap: f32 = b.positive^ ? 1.0 : 0.0
	an: f32 = b.negative^ ? 1.0 : 0.0

	value = ap + an

	active = ap != 0.0 || an != 0.0

	return value, active
}

read_value_axis2 :: proc(b: Control_Axis2) -> (value: [2]f32, active: bool) {
	xp: f32 = b.x.positive^ ? 1.0 : 0.0
	xn: f32 = b.x.negative^ ? 1.0 : 0.0
	yp: f32 = b.y.positive^ ? 1.0 : 0.0
	yn: f32 = b.y.negative^ ? 1.0 : 0.0

	value.x = xp - xn
	value.y = yp - yn

	active = xp != 0.0 || xn != 0.0 || yp != 0.0 || yn != 0.0

	return value, active
}

read_value_pointer :: proc(b: Control_Pointer) -> (value: [2]f32, active: bool) {
	x: f32 = b.x^
	y: f32 = b.y^


	active = x != 0.0 || y != 0.0
	value = {x, y}

	return value, active
}


window_init :: proc(win: ^Window, input: ^Input) {
	check(sdl.Init(sdl.INIT_VIDEO), "Initializing")
	input.sdl_keys = sdl.GetKeyboardState(nil)
	input.lock_mouse = sdl.SetWindowRelativeMouseMode
	check(sdl.Vulkan_LoadLibrary(nil), "Loading Vulkan Library")
	win.w = 800
	win.h = 600

	flags: sdl.WindowFlags = {.VULKAN, .RESIZABLE}
	win.sdl_win = sdl.CreateWindow("Odin Engine", i32(win.w), i32(win.h), flags)

	check(win.sdl_win != nil, "Creating Window")

	win.target_fps = 144
	win.target_time = 1_000_000_000 / u64(win.target_fps)
	win.spin_threshold = 1_000_000
}

input_update_controls :: proc(ctl: []Input_Action) {
	profile_scoped()
	for &action in ctl {
		ov := action.value
		os := action.state

		active: bool
		helper: typeid

		switch v in action.control {
		case Control_Bool:
			action.value, active = read_value_button(action.control.(Control_Bool))
		case Control_Axis:
			action.value, active = read_value_axis(action.control.(Control_Axis))
		case Control_Axis2:
			action.value, active = read_value_axis2(action.control.(Control_Axis2))
		case Control_Pointer:
			action.value, active = read_value_pointer(action.control.(Control_Pointer))
		}

		switch action.state {
		case .Started:
			if active do action.state = .Performing
			else do action.state = .Ended
		case .Performing:
			if !active do action.state = .Ended
		case .Ended:
			if active do action.state = .Started
			else do action.state = .Sleeping
		case .Sleeping:
			if active do action.state = .Started
		}

		if (os != action.state || ov != action.value) && action.callback != nil {
			action.callback(action)
		}

	}
}

poll_events :: proc(
	ren: ^Renderer,
	win: ^Window,
	input: ^Input,
	editor: ^Editor,
	game: ^Game,
	scene: ^Scene,
) {
	profile_scoped()
	buttons := sdl.GetMouseState(&input.relative_mouse_pos.x, &input.relative_mouse_pos.y)
	input.m0 = sdl.MouseButtonFlag.LEFT in buttons
	input.m1 = sdl.MouseButtonFlag.RIGHT in buttons
	input.mouse_delta = {0.0, 0.0}

	event: sdl.Event
	for sdl.PollEvent(&event) {
		imgui_impl_sdl3.ProcessEvent(&event)
		#partial switch (event.type) {
		case .QUIT:
			win.should_close = true
		case .WINDOW_CLOSE_REQUESTED:
			win.should_close = true
		case .MOUSE_MOTION:
			input.mouse_delta.x += event.motion.xrel
			input.mouse_delta.y += event.motion.yrel
		case .WINDOW_RESIZED:
			cam_e := hm.get(&editor.gizmo_scene.entities, editor.cam)
			scene_cam := &cam_e.camera
			game_cam_e := hm.get(&scene.entities, game.main_camera)
			game_cam := &game_cam_e.camera
			w, h: c.int

			sdl.GetWindowSize(win.sdl_win, &w, &h)
			aspect := f32(w) / f32(h)

			scene_cam.aspect = aspect
			game_cam.aspect = aspect

			ren.update_swap = true
		}
	}

}

sleep_spin :: proc(win: ^Window) {
	profile_scoped()
	win.elapsed_time = sdl.GetTicksNS() - win.frame_start

	if win.elapsed_time < win.target_time {
		remaining := win.target_time - win.elapsed_time

		if remaining > win.spin_threshold {
			sdl.DelayNS(remaining - win.spin_threshold)
		}

		for sdl.GetTicksNS() - win.frame_start < win.target_time {
		}
	}
}

time_update :: proc(win: ^Window) {
	profile_scoped()
	win.frame_start = sdl.GetTicksNS()
	win.delta_time = f64(win.frame_start - win.last_time) / 1_000_000_000
	win.last_time = win.frame_start
}
