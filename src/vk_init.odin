package main

import "core:log"
import "core:math"
import "core:slice"

import vma "../../odin-vma"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

begin_one_time_cmd :: proc(ren: ^Renderer) -> vk.CommandBuffer {
	cmd: vk.CommandBuffer

	cai: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ren.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	check(vk.AllocateCommandBuffers(ren.device, &cai, &cmd))

	cbi: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cbi))

	return cmd
}

end_one_time_cmd :: proc(ren: ^Renderer, cmd: vk.CommandBuffer) {
	cmd := cmd
	check(vk.EndCommandBuffer(cmd))

	si: vk.SubmitInfo = {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}

	vk.QueueSubmit(ren.gfx_q, 1, &si, 0)
	vk.QueueWaitIdle(ren.gfx_q)
	vk.FreeCommandBuffers(ren.device, ren.command_pool, 1, &cmd)
}

create_intance :: proc(ren: ^Renderer) {
	sdl_ext_count: u32
	layer_count: u32 = 0
	layers := make([dynamic]cstring)
	defer delete(layers)
	// layers: [d]cstring = {"VK_LAYER_KHRONOS_validation"}
	extensions: [dynamic]cstring


	sdl_ext := sdl.Vulkan_GetInstanceExtensions(&sdl_ext_count)

	for i in 0 ..< sdl_ext_count {
		append(&extensions, sdl_ext[i])
	}

	when ENABLE_VALIDATION {
		append(&layers, "VK_LAYER_KHRONOS_validation")
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	ai := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Odin Engine",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_4,
	}

	ici := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = nil,
		pApplicationInfo        = &ai,
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}

	check(vk.CreateInstance(&ici, nil, &ren.instance), "Creating Instance")
}

//TODO: Actually select the best device
select_physical_device :: proc(ren: ^Renderer) {
	count: u32
	devices: [8]vk.PhysicalDevice

	check(vk.EnumeratePhysicalDevices(ren.instance, &count, nil))
	check(vk.EnumeratePhysicalDevices(ren.instance, &count, &devices[0]))

	ren.physical = devices[0]

	props: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
	}

	vk.GetPhysicalDeviceProperties2(ren.physical, &props)
	log.infof("Device Found: %s", props.properties.deviceName)
}

create_device :: proc(ren: ^Renderer) {
	q_priority: f32
	family_count: u32
	families: [32]vk.QueueFamilyProperties
	ext := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	vk.GetPhysicalDeviceQueueFamilyProperties(ren.physical, &family_count, nil)
	vk.GetPhysicalDeviceQueueFamilyProperties(ren.physical, &family_count, &families[0])


	for i in 0 ..< family_count {
		if .GRAPHICS in families[i].queueFlags {
			sdl_check(sdl.Vulkan_GetPresentationSupport(ren.instance, ren.physical, i))
			ren.gfx_q_family = i
		}
	}

	qci: vk.DeviceQueueCreateInfo = {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = ren.gfx_q_family,
		queueCount       = 1,
		pQueuePriorities = &q_priority,
	}

	f10: vk.PhysicalDeviceFeatures = {
		samplerAnisotropy = true,
	}

	f11: vk.PhysicalDeviceVulkan11Features = {
		sType                = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters = true,
	}

	f12: vk.PhysicalDeviceVulkan12Features = {
		sType                                     = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext                                     = &f11,
		descriptorIndexing                        = true,
		shaderSampledImageArrayNonUniformIndexing = true,
		descriptorBindingVariableDescriptorCount  = true,
		runtimeDescriptorArray                    = true,
		bufferDeviceAddress                       = true,
	}

	f13: vk.PhysicalDeviceVulkan13Features = {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext            = &f12,
		synchronization2 = true,
		dynamicRendering = true,
	}

	dci: vk.DeviceCreateInfo = {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &f13,
		queueCreateInfoCount    = 1,
		pQueueCreateInfos       = &qci,
		enabledExtensionCount   = 1,
		ppEnabledExtensionNames = &ext[0],
		pEnabledFeatures        = &f10,
	}

	check(vk.CreateDevice(ren.physical, &dci, nil, &ren.device), "Creating Device")
	vk.load_proc_addresses_device(ren.device)
	vk.GetDeviceQueue(ren.device, ren.gfx_q_family, 0, &ren.gfx_q)
}

create_allocator :: proc(ren: ^Renderer) {
	f := vma.create_vulkan_functions()

	aci: vma.AllocatorCreateInfo = {
		flags            = {.BUFFER_DEVICE_ADDRESS},
		instance         = ren.instance,
		physicalDevice   = ren.physical,
		device           = ren.device,
		pVulkanFunctions = &f,
		vulkanApiVersion = vk.API_VERSION_1_4,
	}

	check(vma.CreateAllocator(aci, &ren.allocator), "Creating VMA Allocator")
}

create_surface :: proc(ren: ^Renderer, win: ^Window) {
	w, h: i32

	sdl_check(
		sdl.Vulkan_CreateSurface(win.sdl_win, ren.instance, nil, &ren.surface),
		"Creating Vulkan Surface",
	)
	sdl_check(sdl.GetWindowSize(win.sdl_win, &w, &h))
	win.w, win.h = u32(w), u32(h)
}

create_sync_primitives :: proc(ren: ^Renderer) {
	ren.fences = make([]vk.Fence, FIF)
	ren.semaphore_image = make([]vk.Semaphore, FIF)
	ren.semaphore_render = make([]vk.Semaphore, ren.swap_count)

	fci: vk.FenceCreateInfo = {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	sci: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
	}


	for i in 0 ..< FIF {
		check(vk.CreateFence(ren.device, &fci, nil, &ren.fences[i]))
		check(vk.CreateSemaphore(ren.device, &sci, nil, &ren.semaphore_image[i]))
	}

	for i in 0 ..< ren.swap_count {
		check(vk.CreateSemaphore(ren.device, &sci, nil, &ren.semaphore_render[i]))
	}
}

create_command_buffer :: proc(ren: ^Renderer) {
	ren.command_buffers = make([]vk.CommandBuffer, FIF)

	cci: vk.CommandPoolCreateInfo = {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ren.gfx_q_family,
	}

	check(vk.CreateCommandPool(ren.device, &cci, nil, &ren.command_pool))

	cba: vk.CommandBufferAllocateInfo = {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ren.command_pool,
		level              = .PRIMARY,
		commandBufferCount = FIF,
	}

	check(vk.AllocateCommandBuffers(ren.device, &cba, raw_data(ren.command_buffers)))
}

create_shader_modules :: proc(ren: ^Renderer, code: []byte) -> vk.ShaderModule {
	module: vk.ShaderModule

	as_u32 := slice.reinterpret([]u32, code)

	mci: vk.ShaderModuleCreateInfo = {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	check(vk.CreateShaderModule(ren.device, &mci, nil, &module), "Creating Shader Module")

	return module
}

load_default_textures :: proc(ren: ^Renderer, res: ^Resources) {
	img := get_new_image(res)
	white_color: [4]u8 = {255, 255, 255, 255}

	load_image(ren, res, img, nil, &white_color[0], 1, 1, 4)
}

renderer_init :: proc(ren: ^Renderer, win: ^Window, res: ^Resources) {
	vk.load_proc_addresses_global(rawptr(sdl.Vulkan_GetVkGetInstanceProcAddr()))
	assert(vk.CreateInstance != nil, "Vulkan Global Function Pointers Not Loaded")

	create_intance(ren)
	vk.load_proc_addresses_instance(ren.instance)
	assert(vk.CreateDevice != nil, "Vulkan Instance Function Pointers Not Loaded")

	when ENABLE_VALIDATION {
		create_debug_messenger(ren)
	}

	select_physical_device(ren)
	create_device(ren)

	create_allocator(ren)
	create_surface(ren, win)
	swapchain_create(ren, win)
	create_depth_image(ren, win.w, win.h)
	create_sync_primitives(ren)
	create_command_buffer(ren)
	create_sampler(ren)
	load_default_textures(ren, res)
	load_model(ren, res, 1.0, "assets/models/primitives/cube.gltf")
	load_model(ren, res, 1.0, "assets/models/primitives/sphere.gltf")
	load_model(ren, res, 1.0, "assets/models/primitives/capsule.gltf")
	load_model(ren, res, 0.01, "../glTF-Sample-Assets/Models/Sponza/glTF/Sponza.gltf")
	load_model(ren, res, 1.0, "../glTF-Sample-Assets/Models/DamagedHelmet/glTF/DamagedHelmet.gltf")
	create_descriptor_pool(ren)
	create_descriptor_layouts(ren, res)
	descriptor_set_create_tex(ren, res)
	// ren.post_shader = create_shader_modules(ren, SHADER_FULLSCREEN)
	ren.default_shader = create_shader_modules(ren, SHADER_DEFAULT)
	ren.post_pipeline, ren.post_pipeline_layout = create_pipeline(ren)

	ren.test_buff = make([]Buffer, FIF)

	for i in 0 ..< FIF {
		ren.test_buff[i] = create_buffer(
			ren,
			size_of(Mesh_Uniforms),
			{.SHADER_DEVICE_ADDRESS},
			{.HOST_ACCESS_SEQUENTIAL_WRITE, .HOST_ACCESS_ALLOW_TRANSFER_INSTEAD, .MAPPED},
		)
	}
}
