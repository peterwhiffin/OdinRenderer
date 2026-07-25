package renderer

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
	bindings: []vk.DescriptorSetLayoutBinding = {
		{
			binding = 0,
			descriptorType = .SAMPLED_IMAGE,
			descriptorCount = res.images.count,
			stageFlags = {.FRAGMENT},
		},
		{binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
	}

	dci: vk.DescriptorSetLayoutCreateInfo = {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings    = raw_data(bindings),
	}

	check(vk.CreateDescriptorSetLayout(ren.device, &dci, nil, &ren.desc_layout_tex))
}

create_descriptor_sets :: proc(ren: ^Renderer, res: ^Resources) {
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
