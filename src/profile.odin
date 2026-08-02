package main

import "base:runtime"
import "core:prof/spall"
import "core:sync"

Profile_Level :: enum {
	None   = 0,
	Custom = 1,
	Scoped = 2,
	All    = 3,
}

PROFILE :: Profile_Level(#config(PROFILE, Profile_Level.None))

when PROFILE != .None {
	spall_ctx: spall.Context
	@(thread_local)
	spall_buffer: spall.Buffer
	buffer_backing: []u8
}

profile_init :: proc(filename := "SpallProfile.spall", buf_size: int = spall.BUFFER_DEFAULT_SIZE) {
	when PROFILE != .None {
		spall_ctx = spall.context_create(filename)
		buffer_backing := make([]u8, buf_size)
		spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
	}
}

profile_clean :: proc() {
	when PROFILE != .None {
		spall.buffer_destroy(&spall_ctx, &spall_buffer)
		delete(buffer_backing)
		spall.context_destroy(&spall_ctx)
	}
}

when PROFILE >= .All {
	@(instrumentation_enter)
	spall_enter :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}

	@(instrumentation_exit)
	spall_exit :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

@(private)
_profile_scoped_end :: proc(_: string, _ := #caller_location) {
	when PROFILE >= .Scoped {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

@(deferred_in = _profile_scoped_end)
profile_scoped :: proc(label := "", loc := #caller_location) {
	when PROFILE >= .Scoped {
		spall._buffer_begin(&spall_ctx, &spall_buffer, label, "", loc)
	}
}

profile_begin :: proc(label := "", loc := #caller_location) {
	when PROFILE >= .Custom {
		spall._buffer_begin(&spall_ctx, &spall_buffer, label, "", loc)
	}
}

profile_end :: proc(label := "", loc := #caller_location) {
	when PROFILE >= .Custom {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}
