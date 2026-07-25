package renderer

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

g_ctx: runtime.Context

check :: proc(result: vk.Result, msg: cstring = nil, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("VK::%v\n%s", result, msg, location = loc)
	} else if msg != nil {
		log.infof("VK::%s", msg, location = loc)
	}
}

debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {

	// context = runtime.default_context()
	context = g_ctx

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "vulkan[%v]: %s", messageTypes, pCallbackData.pMessage)
	return false
}

create_debug_messenger :: proc(ren: ^Renderer) {
	severity_flags: vk.DebugUtilsMessageSeverityFlagsEXT = {.ERROR, .WARNING}
	type_flags: vk.DebugUtilsMessageTypeFlagsEXT = {.GENERAL, .PERFORMANCE, .VALIDATION}

	dmci: vk.DebugUtilsMessengerCreateInfoEXT = {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = severity_flags,
		messageType     = type_flags,
		pfnUserCallback = debug_callback,
	}

	check(
		vk.CreateDebugUtilsMessengerEXT(ren.instance, &dmci, nil, &ren.messenger),
		"Creating Debug Messenger",
	)
}
