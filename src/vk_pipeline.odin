package main

import vk "vendor:vulkan"

create_pipeline :: proc(ren: ^Renderer) -> (vk.Pipeline, vk.PipelineLayout) {
	pipeline: vk.Pipeline
	layout: vk.PipelineLayout

	pcr: vk.PushConstantRange = {
		stageFlags = {.VERTEX, .FRAGMENT},
		size       = size_of(Push_Constants),
	}

	layouts: []vk.DescriptorSetLayout = {
		ren.desc_layout_tex,
		ren.desc_layout_entity,
		ren.desc_layout_pick,
	}

	lci: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(layouts)),
		pSetLayouts            = raw_data(layouts),
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pcr,
	}

	check(vk.CreatePipelineLayout(ren.device, &lci, nil, &layout))

	vid: vk.VertexInputBindingDescription = {
		binding   = 0,
		stride    = size_of(Vertex),
		inputRate = .VERTEX,
	}

	vad: []vk.VertexInputAttributeDescription = {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT},
		{location = 1, binding = 0, format = .R32G32B32_SFLOAT, offset = size_of(f32) * 3},
		{location = 2, binding = 0, format = .R32G32_SFLOAT, offset = size_of(f32) * 6},
	}

	vis: vk.PipelineVertexInputStateCreateInfo = {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &vid,
		vertexAttributeDescriptionCount = 3,
		pVertexAttributeDescriptions    = raw_data(vad),
	}

	ias: vk.PipelineInputAssemblyStateCreateInfo = {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	stages: []vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = ren.default_shader,
			pName = "vertMain",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = ren.default_shader,
			pName = "fragMain",
		},
	}

	vps: vk.PipelineViewportStateCreateInfo = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	states: []vk.DynamicState = {.VIEWPORT, .SCISSOR}

	ds: vk.PipelineDynamicStateCreateInfo = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(states),
	}

	dci: vk.PipelineDepthStencilStateCreateInfo = {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .GREATER,
	}

	fmt: vk.Format = .R8G8B8A8_SRGB
	rci: vk.PipelineRenderingCreateInfo = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &fmt,
		depthAttachmentFormat   = ren.depth_format,
	}

	//TODO: read the spec on blending
	cbs: vk.PipelineColorBlendAttachmentState = {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .SRC_ALPHA,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	bci: vk.PipelineColorBlendStateCreateInfo = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &cbs,
	}

	rasci: vk.PipelineRasterizationStateCreateInfo = {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		// polygonMode = .LINE,
		lineWidth   = 1.0,
	}

	msci: vk.PipelineMultisampleStateCreateInfo = {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	pci: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rci,
		stageCount          = 2,
		pStages             = raw_data(stages),
		pVertexInputState   = &vis,
		pInputAssemblyState = &ias,
		pViewportState      = &vps,
		pRasterizationState = &rasci,
		pMultisampleState   = &msci,
		pDepthStencilState  = &dci,
		pColorBlendState    = &bci,
		pDynamicState       = &ds,
		layout              = layout,
	}

	check(
		vk.CreateGraphicsPipelines(ren.device, 0, 1, &pci, nil, &pipeline),
		"Creating Graphics Pipeline",
	)

	return pipeline, layout
}

create_post_pipeline :: proc(ren: ^Renderer) -> (vk.Pipeline, vk.PipelineLayout) {
	pipeline: vk.Pipeline
	layout: vk.PipelineLayout

	pcr: vk.PushConstantRange = {}


	layouts: []vk.DescriptorSetLayout = {ren.desc_layout_post}

	lci: vk.PipelineLayoutCreateInfo = {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(layouts)),
		pSetLayouts            = raw_data(layouts),
		pushConstantRangeCount = 0,
		pPushConstantRanges    = &pcr,
	}

	check(vk.CreatePipelineLayout(ren.device, &lci, nil, &layout))

	vid: []vk.VertexInputBindingDescription = {}

	vad: []vk.VertexInputAttributeDescription = {}

	vis: vk.PipelineVertexInputStateCreateInfo = {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = u32(len(vid)),
		pVertexBindingDescriptions      = raw_data(vid),
		vertexAttributeDescriptionCount = u32(len(vad)),
		pVertexAttributeDescriptions    = raw_data(vad),
	}

	ias: vk.PipelineInputAssemblyStateCreateInfo = {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	stages: []vk.PipelineShaderStageCreateInfo = {
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = ren.post_shader,
			pName = "vertMain",
		},
		{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = ren.post_shader,
			pName = "fragMain",
		},
	}

	vps: vk.PipelineViewportStateCreateInfo = {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	states: []vk.DynamicState = {.VIEWPORT, .SCISSOR}

	ds: vk.PipelineDynamicStateCreateInfo = {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(states),
	}

	dci: vk.PipelineDepthStencilStateCreateInfo = {
		sType           = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = false,
		depthCompareOp  = .GREATER,
	}

	// fmt: vk.Format = .R8G8B8A8_SRGB
	rci: vk.PipelineRenderingCreateInfo = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &ren.swap_format,
	}

	//TODO: read the spec on blending
	cbs: vk.PipelineColorBlendAttachmentState = {
		blendEnable         = false,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .SRC_ALPHA,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	bci: vk.PipelineColorBlendStateCreateInfo = {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &cbs,
	}

	rasci: vk.PipelineRasterizationStateCreateInfo = {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		// polygonMode = .LINE,
		lineWidth   = 1.0,
	}

	msci: vk.PipelineMultisampleStateCreateInfo = {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}

	pci: vk.GraphicsPipelineCreateInfo = {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rci,
		stageCount          = 2,
		pStages             = raw_data(stages),
		pVertexInputState   = &vis,
		pInputAssemblyState = &ias,
		pViewportState      = &vps,
		pRasterizationState = &rasci,
		pMultisampleState   = &msci,
		pDepthStencilState  = &dci,
		pColorBlendState    = &bci,
		pDynamicState       = &ds,
		layout              = layout,
	}

	check(
		vk.CreateGraphicsPipelines(ren.device, 0, 1, &pci, nil, &pipeline),
		"Creating Graphics Pipeline",
	)

	return pipeline, layout
}
