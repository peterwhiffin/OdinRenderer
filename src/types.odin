package main

import vma "../../odin-vma"
import hm "core:container/handle_map"
import "core:container/xar"
import "core:math/linalg"
import b3 "vendor:box3d"
import vk "vendor:vulkan"

ENABLE_VALIDATION :: #config(ENABLE_VALIDATION, ODIN_DEBUG)
EDITOR :: #config(EDITOR, true)
FIF :: 2
SHADER_PATH :: "shaders/"

SHADER_FULLSCREEN :: #load("../build/lin/fullscreen.spv")
SHADER_DEFAULT :: #load("../build/lin/default.spv")
SHADER_IMGUI_VERT :: #load("../build/lin/imgui_vert.spv")
SHADER_IMGUI_FRAG :: #load("../build/lin/imgui_frag.spv")
PHYSICS_TIMESTEP :: f32(1.0) / f32(60.0)

Handle :: hm.Handle64

Post_Settings :: struct {
	pixel_size:     [2]f32,
	fade:           [2]f32,
	min_brightness: [4]f32,
	crt_enabled:    bool,
}

Picking_Hit :: struct {
	depth:  f32,
	handle: Handle,
}

Picking_Data :: struct {
	hits:      [4096]Picking_Hit,
	hit_count: u32,
}

Rigidbody :: struct {
	entity:   ^Entity,
	body_id:  b3.BodyId,
	shape_id: b3.ShapeId,
}

Transform :: struct {
	entity:          Handle,
	world_transform: linalg.Matrix4x4f32,
	rot:             quaternion128,
	pos:             [3]f32,
	euler_angles:    [3]f32,
	scale:           [3]f32,
	is_dirty:        bool,
}

Camera :: struct {
	view:   linalg.Matrix4x4f32,
	proj:   linalg.Matrix4x4f32,
	fov:    f32,
	aspect: f32,
	near:   f32,
	far:    f32,
}

Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
	Transform,
	Mesh_Renderer,
	Rigidbody,
	Spot_Light,
	Point_Light,
	Directional_light,
	Camera,
}

Mesh_Uniforms :: struct {
	model:         linalg.Matrix4x4f32,
	normal_matrix: linalg.Matrix4x4f32,
	color:         [4]f32,
	entity_handle: Handle,
}

Component :: struct {}


Spotlight :: struct {
	using _: Component,
}


Entity :: struct {
	mesh_renderer: Mesh_Renderer,
	transform:     Transform,
	rigidbody:     Rigidbody,
	comps:         [dynamic]Component,
	camera:        Camera,
	name:          string,
	handle:        Handle,
	parent:        Handle,
	children:      [dynamic]Handle,
	flags:         Entity_Flags,
}

Physics :: struct {
	world:      b3.WorldId,
	time_accum: f32,
}

Resources :: struct {
	mesh_map:  map[string]^Mesh,
	image_map: map[string]^Image,
	meshes:    xar.Array(Mesh, 4),
	images:    xar.Array(Image, 4),
}

Vertex :: struct {
	pos:  [3]f32,
	norm: [3]f32,
	uv:   [2]f32,
}

Push_Constants :: struct {
	addr:      vk.DeviceAddress,
	tex_index: u32,
}

Frame_Uniforms :: struct {
	proj:        linalg.Matrix4x4f32,
	view:        linalg.Matrix4x4f32,
	light_dir:   [4]f32,
	light_color: [4]f32,
	mouse_pos:   [2]u32,
	ambient:     f32,
}

Submesh :: struct {
	tex_index:    u32,
	index_offset: uint,
	index_count:  uint,
}

Scene :: struct {
	name:     string,
	entities: hm.Dynamic_Handle_Map(Entity, Handle),
}


Mesh :: struct {
	vertex_count: u64,
	index_count:  u64,
	index_offset: u64,
	buffer:       Buffer,
	name:         string,
	submeshes:    [dynamic]Submesh,
}

Buffer :: struct {
	buff:       vk.Buffer,
	allocation: vma.Allocation,
	alloc_info: vma.AllocationInfo,
	address:    vk.DeviceAddress,
}

Mesh_Renderer :: struct {
	mesh:            ^Mesh,
	normal_matrix:   linalg.Matrix4x4f32,
	uniform_buffers: []Buffer,
	desc_sets:       []vk.DescriptorSet,
	color:           [4]f32,
	material:        u32,
}

Image :: struct {
	image:      vk.Image,
	view:       vk.ImageView,
	allocation: vma.Allocation,
	fmt:        vk.Format,
}

Texture :: struct {
	name:        string,
	image_index: u32,
}

Renderer :: struct {
	instance:                vk.Instance,
	physical:                vk.PhysicalDevice,
	device:                  vk.Device,
	allocator:               vma.Allocator,
	surface:                 vk.SurfaceKHR,
	swapchain:               vk.SwapchainKHR,
	command_pool:            vk.CommandPool,
	gfx_q:                   vk.Queue,
	desc_pool:               vk.DescriptorPool,
	desc_layout_entity:      vk.DescriptorSetLayout,
	desc_layout_tex:         vk.DescriptorSetLayout,
	desc_layout_post:        vk.DescriptorSetLayout,
	desc_layout_pick:        vk.DescriptorSetLayout,
	desc_set_tex:            vk.DescriptorSet,
	sampler:                 vk.Sampler,
	forward_pipeline:        vk.Pipeline,
	post_pipeline:           vk.Pipeline,
	forward_pipeline_layout: vk.PipelineLayout,
	post_pipeline_layout:    vk.PipelineLayout,
	default_shader:          vk.ShaderModule,
	post_shader:             vk.ShaderModule,
	imgui_shader:            vk.ShaderModule,
	depth_format:            vk.Format,
	swap_format:             vk.Format,
	messenger:               vk.DebugUtilsMessengerEXT,
	fences:                  []vk.Fence,
	semaphore_render:        []vk.Semaphore,
	semaphore_image:         []vk.Semaphore,
	command_buffers:         []vk.CommandBuffer,
	desc_set_post:           []vk.DescriptorSet,
	desc_set_pick:           []vk.DescriptorSet,
	test_buff:               []Buffer,
	post_uniform_buffers:    []Buffer,
	picking_buffers:         []Buffer,
	swap_images:             []Image,
	forward_images:          []Image,
	depth_image:             Image,
	post_settings:           Post_Settings,
	per_frame_uniform:       Frame_Uniforms,
	picker:                  Picking_Data,
	post_size:               [2]u32,
	swap_count:              u32,
	gfx_q_family:            u32,
	frame_index:             u32,
	prev_frame:              u32,
	image_index:             u32,
	selected_entity:         Handle,
	update_swap:             bool,
}
