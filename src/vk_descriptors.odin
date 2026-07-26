package main

import "core:sys/llvm"
import vk "vendor:vulkan"

create_descriptor_pool :: proc(ren: ^Renderer) {
	pool_sizes: []vk.DescriptorPoolSize = {
		{type = .UNIFORM_BUFFER, descriptorCount = 1000},
		{type = .SAMPLED_IMAGE, descriptorCount = 1000},
		{type = .SAMPLER, descriptorCount = 100},
	}

	pci: vk.DescriptorPoolCreateInfo = {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 10000,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
	}

	check(vk.CreateDescriptorPool(ren.device, &pci, nil, &ren.desc_pool))
}

create_descriptor_layouts :: proc(ren: ^Renderer, res: ^Resources) {
	tex_bind: []vk.DescriptorSetLayoutBinding = {
		{
			binding = 0,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = res.images.count,
			stageFlags = {.FRAGMENT},
		},
		{binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
	}

	tex_ci: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(tex_bind),
	}

	check(vk.CreateDescriptorSetLayout(ren.device, &tex_ci, nil, &ren.desc_layout_tex))


	entity_bind: []vk.DescriptorSetLayoutBinding = {
		{
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
	}

	entity_ci: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = raw_data(entity_bind),
	}

	check(vk.CreateDescriptorSetLayout(ren.device, &entity_ci, nil, &ren.desc_layout_entity))
}

descriptor_set_create_tex :: proc(ren: ^Renderer, res: ^Resources) {
	dai: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ren.desc_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &ren.desc_layout_tex,
	}

	check(vk.AllocateDescriptorSets(ren.device, &dai, &ren.desc_set_tex))

	image_infos := make([dynamic]vk.DescriptorImageInfo)
	defer delete(image_infos)

	for i in 0 ..< res.images.count {
		info: vk.DescriptorImageInfo = {
			imageView   = res.images.data[i].view,
			imageLayout = .READ_ONLY_OPTIMAL,
		}

		append(&image_infos, info)
	}

	sampler_info: vk.DescriptorImageInfo = {
		sampler = ren.sampler,
	}

	writes: []vk.WriteDescriptorSet = {
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = ren.desc_set_tex,
			dstBinding = 0,
			descriptorCount = res.images.count,
			descriptorType = .SAMPLED_IMAGE,
			pImageInfo = raw_data(image_infos),
		},
		{
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = ren.desc_set_tex,
			dstBinding = 1,
			descriptorCount = 1,
			descriptorType = .SAMPLER,
			pImageInfo = &sampler_info,
		},
	}

	vk.UpdateDescriptorSets(ren.device, u32(len(writes)), raw_data(writes), 0, nil)
}

descriptor_set_create_mesh :: proc(ren: ^Renderer, e: ^Entity) {
	mr := &e.mesh_renderer

	layouts: [FIF]vk.DescriptorSetLayout

	for &l in layouts {
		l = ren.desc_layout_entity
	}

	dai: vk.DescriptorSetAllocateInfo = {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ren.desc_pool,
		descriptorSetCount = FIF,
		pSetLayouts        = &layouts[0],
	}

	check(vk.AllocateDescriptorSets(ren.device, &dai, raw_data(mr.desc_sets)))

	for set, i in mr.desc_sets {
		dbi: vk.DescriptorBufferInfo = {
			buffer = mr.uniform_buffers[i].buff,
			offset = 0,
			range  = size_of(Mesh_Uniforms),
		}

		writes: vk.WriteDescriptorSet = {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = set,
			dstBinding      = 0,
			dstArrayElement = 0,
			descriptorCount = 1,
			descriptorType  = .UNIFORM_BUFFER,
			pBufferInfo     = &dbi,
		}

		vk.UpdateDescriptorSets(ren.device, 1, &writes, 0, nil)
	}
}
