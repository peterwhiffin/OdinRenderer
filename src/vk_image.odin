package main

import vma "../../odin-vma"
import vk "vendor:vulkan"

create_image :: proc(
	ren: ^Renderer,
	ext: vk.Extent3D,
	mip_levels: u32,
	samples: vk.SampleCountFlags,
	usage: vk.ImageUsageFlags,
	fmt: vk.Format,
	view_aspect: vk.ImageAspectFlags,
) -> Image {
	img: Image

	ici: vk.ImageCreateInfo = {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = fmt,
		extent        = ext,
		mipLevels     = mip_levels,
		arrayLayers   = 1,
		samples       = samples,
		tiling        = .OPTIMAL,
		usage         = usage,
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	aci: vma.AllocationCreateInfo = {
		flags = {.DEDICATED_MEMORY},
		usage = .AUTO,
	}

	check(vma.CreateImage(ren.allocator, ici, aci, &img.image, &img.allocation, nil))
	vma.SetAllocationName(ren.allocator, img.allocation, "Depth Image")

	sr: vk.ImageSubresourceRange = {
		aspectMask     = view_aspect,
		baseMipLevel   = 0,
		levelCount     = mip_levels,
		baseArrayLayer = 0,
		layerCount     = 1,
	}

	vci: vk.ImageViewCreateInfo = {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		image            = img.image,
		viewType         = .D2,
		format           = fmt,
		subresourceRange = sr,
	}

	check(vk.CreateImageView(ren.device, &vci, nil, &img.view))

	return img
}

create_depth_image :: proc(ren: ^Renderer, width: u32, height: u32) {
	fmts: []vk.Format = {.D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}
	ren.depth_format = .UNDEFINED

	props: vk.FormatProperties2 = {
		sType = .FORMAT_PROPERTIES_2,
	}

	for f in fmts {
		vk.GetPhysicalDeviceFormatProperties2(ren.physical, f, &props)

		if .DEPTH_STENCIL_ATTACHMENT in props.formatProperties.optimalTilingFeatures {
			ren.depth_format = f
			break
		}
	}

	ext: vk.Extent3D = {
		width  = width,
		height = height,
		depth  = 1,
	}

	ren.depth_image = create_image(
		ren,
		ext,
		1,
		{._1},
		{.DEPTH_STENCIL_ATTACHMENT},
		ren.depth_format,
		{.DEPTH},
	)
}

create_sampler :: proc(ren: ^Renderer) {
	sci: vk.SamplerCreateInfo = {
		sType            = .SAMPLER_CREATE_INFO,
		minFilter        = .NEAREST,
		magFilter        = .NEAREST,
		mipmapMode       = .LINEAR,
		anisotropyEnable = true,
		maxAnisotropy    = 8.0,
		maxLod           = 0,
	}

	check(vk.CreateSampler(ren.device, &sci, nil, &ren.sampler))
}

transition_image :: proc(
	ren: ^Renderer,
	img: Image,
	cmd: vk.CommandBuffer,
	src_stage: vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	dst_stage: vk.PipelineStageFlags2,
	dst_access: vk.AccessFlags2,
	old: vk.ImageLayout,
	new: vk.ImageLayout,
	aspect: vk.ImageAspectFlags,
	mip_levels: u32,
) {


	barrier: []vk.ImageMemoryBarrier2 = {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = src_stage,
			srcAccessMask = src_access,
			dstStageMask = dst_stage,
			dstAccessMask = dst_access,
			oldLayout = old,
			newLayout = new,
			image = img.image,
			subresourceRange = {aspectMask = aspect, levelCount = mip_levels, layerCount = 1},
		},
	}

	di: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = raw_data(barrier),
	}

	vk.CmdPipelineBarrier2(cmd, &di)
}
