package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_sdl3"
import "../../odin-imgui/imgui_impl_vulkan"
import "core:fmt"
import "core:log"

import sdl "vendor:sdl3"

Window :: struct {
	sdl_win:        ^sdl.Window,
	w:              u32,
	h:              u32,
	frame_start:    u64,
	last_time:      u64,
	target_time:    u64,
	elapsed_time:   u64,
	spin_threshold: u64,
	delta_time:     f64,
	target_fps:     u32,
	should_close:   bool,
}

Input :: struct {
	sdl_keys:           [^]bool,
	lock_mouse:         proc "c" (window: ^sdl.Window, enabled: bool) -> bool,
	relative_mouse_pos: [2]f32,
	mouse_delta:        [2]f32,
	wasd:               [2]f32,
	m0:                 bool,
	m1:                 bool,
}

sdl_check :: proc(result: bool, msg: cstring = nil) {
	if !result {
		log.error("SDL Call Failed!")
		log.errorf("%s%s", "SDL::", msg)
	} else if msg != nil {
		log.infof("%s%s", "SDL::", msg)
	}
}

window_init :: proc(win: ^Window, input: ^Input) {
	sdl_check(sdl.Init(sdl.INIT_VIDEO), "Initializing")
	input.sdl_keys = sdl.GetKeyboardState(nil)
	input.lock_mouse = sdl.SetWindowRelativeMouseMode
	sdl_check(sdl.Vulkan_LoadLibrary(nil), "Loading Vulkan Library")
	win.w = 800
	win.h = 600

	// flags: sdl.WindowFlags = {.VULKAN, .RESIZABLE}
	flags: sdl.WindowFlags = {.VULKAN}
	win.sdl_win = sdl.CreateWindow("Odin Engine", i32(win.w), i32(win.h), flags)

	sdl_check(win.sdl_win != nil, "Creating Window")

	win.target_fps = 144
	win.target_time = 1_000_000_000 / u64(win.target_fps)
	win.spin_threshold = 1_000_000
}

input_update :: proc(input: ^Input) {
	buttons := sdl.GetMouseState(&input.relative_mouse_pos.x, &input.relative_mouse_pos.y)

	input.m1 = sdl.MouseButtonFlag.RIGHT in buttons
	input.m0 = sdl.MouseButtonFlag.LEFT in buttons

	W: f32 = input.sdl_keys[sdl.Scancode.W] ? 1.0 : 0.0
	A: f32 = input.sdl_keys[sdl.Scancode.A] ? 1.0 : 0.0
	S: f32 = input.sdl_keys[sdl.Scancode.S] ? 1.0 : 0.0
	D: f32 = input.sdl_keys[sdl.Scancode.D] ? 1.0 : 0.0

	input.wasd = {D - A, W - S}
}

poll_events :: proc(win: ^Window, input: ^Input) {
	event: sdl.Event

	input.mouse_delta.x = 0
	input.mouse_delta.y = 0

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
		}
	}
}

sleep_spin :: proc(win: ^Window) {
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
	win.frame_start = sdl.GetTicksNS()
	win.delta_time = f64(win.frame_start - win.last_time) / 1_000_000_000.0
	win.last_time = win.frame_start
}
