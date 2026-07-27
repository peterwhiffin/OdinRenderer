package main

import vma "../../odin-vma"
import "core:math/linalg"
import b3 "vendor:box3d"
import vk "vendor:vulkan"

ENABLE_VALIDATION :: #config(ENABLE_VALIDATION, ODIN_DEBUG)
FIF :: 2
SHADER_PATH :: "shaders/"

SHADER_FULLSCREEN :: #load("../build/lin/fullscreen.spv")
SHADER_DEFAULT :: #load("../build/lin/default.spv")
PHYSICS_TIMESTEP :: f32(1.0) / f32(60.0)

Rigidbody :: struct {
	entity:   ^Entity,
	body_id:  b3.BodyId,
	shape_id: b3.ShapeId,
}

Transform :: struct {
	entity:          ^Entity,
	world_transform: linalg.Matrix4x4f32,
	parent:          ^Transform,
	children:        [dynamic]^Transform,
	pos:             [3]f32,
	rot:             quaternion128,
	euler_angles:    [3]f32,
	scale:           [3]f32,
	is_dirty:        bool,
}

Camera :: struct {
	fov:    f32,
	aspect: f32,
	near:   f32,
	far:    f32,
	view:   linalg.Matrix4x4f32,
	proj:   linalg.Matrix4x4f32,
}

Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
	MESH_RENDERER,
	RIGIDBODY,
	SPOT_LIGHT,
	POINT_LIGHT,
	DIRECTIONAL_LIGHT,
	CAMERA,
}

Mesh_Uniforms :: struct {
	model:         linalg.Matrix4x4f32,
	normal_matrix: linalg.Matrix4x4f32,
	color:         [4]f32,
}

Entity :: struct {
	name:          cstring,
	flags:         Entity_Flags,
	transform:     Transform,
	mesh_renderer: Mesh_Renderer,
	rigidbody:     Rigidbody,
	camera:        Camera,
}

Physics :: struct {
	world:      b3.WorldId,
	time_accum: f32,
}

Array :: struct($T: typeid) {
	data:  []T,
	count: u32,
}

Resources :: struct {
	meshes: Array(Mesh),
	images: Array(Image),
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
	proj: linalg.Matrix4x4f32,
	view: linalg.Matrix4x4f32,
}

Submesh :: struct {
	index_offset: uint,
	index_count:  uint,
	tex_index:    u32,
}

Scene :: struct {
	entities: Array(Entity),
}

Mesh :: struct {
	name:         cstring,
	vertex_count: u64,
	index_count:  u64,
	index_offset: u64,
	submeshes:    [dynamic]Submesh,
	buffer:       Buffer,
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
	material:        u32,
	color:           [4]f32,
}

Image :: struct {
	image:      vk.Image,
	view:       vk.ImageView,
	allocation: vma.Allocation,
}

Renderer :: struct {
	instance:             vk.Instance,
	physical:             vk.PhysicalDevice,
	device:               vk.Device,
	allocator:            vma.Allocator,
	surface:              vk.SurfaceKHR,
	swapchain:            vk.SwapchainKHR,
	swap_images:          []Image,
	swap_count:           u32,
	swap_format:          vk.Format,
	fences:               []vk.Fence,
	semaphore_render:     []vk.Semaphore,
	semaphore_image:      []vk.Semaphore,
	command_buffers:      []vk.CommandBuffer,
	command_pool:         vk.CommandPool,
	desc_pool:            vk.DescriptorPool,
	desc_layout_entity:   vk.DescriptorSetLayout,
	desc_layout_tex:      vk.DescriptorSetLayout,
	desc_set_tex:         vk.DescriptorSet,
	sampler:              vk.Sampler,
	post_pipeline_layout: vk.PipelineLayout,
	post_pipeline:        vk.Pipeline,
	// post_shader:          vk.ShaderModule,
	default_shader:       vk.ShaderModule,
	depth_image:          Image,
	depth_format:         vk.Format,
	messenger:            vk.DebugUtilsMessengerEXT,
	gfx_q:                vk.Queue,
	gfx_q_family:         u32,
	frame_index:          u32,
	image_index:          u32,
	test_buff:            []Buffer,
	entities:             Array(Entity),
	update_swap:          bool,
}
