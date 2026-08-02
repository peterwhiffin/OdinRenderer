package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_vulkan"
import hm "core:container/handle_map"
import "core:math/linalg"
import "core:mem"
import "core:slice"

import vk "vendor:vulkan"

begin_cmd :: proc(cmd: vk.CommandBuffer) {
	vk.ResetCommandBuffer(cmd, {})

	cbi: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cbi))
}

draw_forward :: proc(
	cmd: vk.CommandBuffer,
	ren: ^Renderer,
	win: ^Window,
	cam: ^Camera,
	s: ^Scene,
) {
	profile_scoped()
	frame := ren.frame_index

	out_barrier: []vk.ImageMemoryBarrier2 = {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {},
			dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
			oldLayout = .UNDEFINED,
			newLayout = .ATTACHMENT_OPTIMAL,
			image = ren.forward_images[frame].image,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = {.LATE_FRAGMENT_TESTS},
			srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			dstStageMask = {.EARLY_FRAGMENT_TESTS},
			dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
			oldLayout = .UNDEFINED,
			newLayout = .ATTACHMENT_OPTIMAL,
			image = ren.depth_image.image,
			subresourceRange = {aspectMask = {.DEPTH, .STENCIL}, levelCount = 1, layerCount = 1},
		},
	}

	out_di: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 2,
		pImageMemoryBarriers    = raw_data(out_barrier),
	}

	vk.CmdPipelineBarrier2(cmd, &out_di)

	cai: vk.RenderingAttachmentInfo = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = ren.forward_images[frame].view,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
	}

	dai: vk.RenderingAttachmentInfo = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = ren.depth_image.view,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		clearValue = {depthStencil = {depth = 0.0, stencil = 0}},
	}

	ri: vk.RenderingInfo = {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = ren.post_size.x, height = ren.post_size.y}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &cai,
		pDepthAttachment = &dai,
	}

	vk.CmdBeginRendering(cmd, &ri)

	vp: vk.Viewport = {
		width    = f32(ren.post_size.x),
		height   = f32(ren.post_size.y),
		minDepth = 1.0,
		maxDepth = 0.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &vp)

	sc: vk.Rect2D = {
		extent = {width = ren.post_size.x, height = ren.post_size.y},
	}

	vk.CmdSetScissor(cmd, 0, 1, &sc)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ren.forward_pipeline)


	mn := win.input.relative_mouse_pos / [2]f32{f32(win.w), f32(win.h)}

	mx := f32(ren.post_size.x) * mn.x
	my := f32(ren.post_size.y) * mn.y


	ren.per_frame_uniform.proj = cam.proj
	ren.per_frame_uniform.view = cam.view
	ren.per_frame_uniform.mouse_pos = {u32(mx), u32(my)}

	mem.copy(
		ren.test_buff[frame].alloc_info.pMappedData,
		&ren.per_frame_uniform,
		size_of(Frame_Uniforms),
	)

	offset: u32 = 0
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ren.forward_pipeline_layout,
		0,
		1,
		&ren.desc_set_tex,
		0,
		&offset,
	)


	pc: Push_Constants = {
		addr      = ren.test_buff[frame].address,
		tex_index = 0,
	}

	vk.CmdPushConstants(
		cmd,
		ren.forward_pipeline_layout,
		{.FRAGMENT, .VERTEX},
		0,
		size_of(Push_Constants),
		&pc,
	)

	voffset: vk.DeviceSize = 0

	it := hm.iterator_make(&s.entities)

	for e, h in hm.iterate(&it) {
		if .MESH_RENDERER not_in e.flags do continue

		mr := &e.mesh_renderer
		m := mr.mesh


		voffset: vk.DeviceSize = 0
		vk.CmdBindVertexBuffers(cmd, 0, 1, &m.buffer.buff, &voffset)
		vk.CmdBindIndexBuffer(cmd, m.buffer.buff, vk.DeviceSize(m.index_offset), .UINT32)

		color: [4]f32 = mr.color
		if h == ren.selected_entity {
			color = {1.0, 0.0, 1.0, 1.0}
		}


		muni: Mesh_Uniforms = {
			model         = e.transform.world_transform,
			normal_matrix = mr.normal_matrix,
			color         = color,
			entity_handle = h,
		}


		mem.copy(mr.uniform_buffers[frame].alloc_info.pMappedData, &muni, size_of(Mesh_Uniforms))

		vk.CmdBindDescriptorSets(
			cmd,
			.GRAPHICS,
			ren.forward_pipeline_layout,
			1,
			1,
			&mr.desc_sets[frame],
			0,
			nil,
		)

		vk.CmdBindDescriptorSets(
			cmd,
			.GRAPHICS,
			ren.forward_pipeline_layout,
			2,
			1,
			&ren.desc_set_pick[frame],
			0,
			nil,
		)

		for &sm, i in mr.mesh.submeshes {
			pc: Push_Constants = {
				addr      = ren.test_buff[frame].address,
				tex_index = sm.tex_index,
			}

			vk.CmdPushConstants(
				cmd,
				ren.forward_pipeline_layout,
				{.FRAGMENT, .VERTEX},
				0,
				size_of(Push_Constants),
				&pc,
			)

			vk.CmdDrawIndexed(cmd, u32(sm.index_count), 1, u32(sm.index_offset), 0, 0)
		}
	}

	vk.CmdEndRendering(cmd)
}


draw_post :: proc(cmd: vk.CommandBuffer, ren: ^Renderer, win: ^Window) {
	profile_scoped()
	frame := ren.frame_index

	out_barrier: []vk.ImageMemoryBarrier2 = {
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
			dstStageMask = {.FRAGMENT_SHADER},
			dstAccessMask = {.COLOR_ATTACHMENT_READ},
			oldLayout = .ATTACHMENT_OPTIMAL,
			newLayout = .READ_ONLY_OPTIMAL,
			image = ren.forward_images[frame].image,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		},
		{
			sType = .IMAGE_MEMORY_BARRIER_2,
			srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {},
			dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
			oldLayout = .UNDEFINED,
			newLayout = .ATTACHMENT_OPTIMAL,
			image = ren.swap_images[ren.image_index].image,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		},
	}

	out_di: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 2,
		pImageMemoryBarriers    = raw_data(out_barrier),
	}

	vk.CmdPipelineBarrier2(cmd, &out_di)

	cai: vk.RenderingAttachmentInfo = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = ren.swap_images[ren.image_index].view,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
	}

	ri: vk.RenderingInfo = {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = win.w, height = win.h}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &cai,
	}

	vk.CmdBeginRendering(cmd, &ri)

	vp: vk.Viewport = {
		width    = f32(win.w),
		height   = f32(win.h),
		minDepth = 1.0,
		maxDepth = 0.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &vp)

	sc: vk.Rect2D = {
		extent = {width = win.w, height = win.h},
	}

	vk.CmdSetScissor(cmd, 0, 1, &sc)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ren.post_pipeline)

	mem.copy(
		ren.post_uniform_buffers[frame].alloc_info.pMappedData,
		&ren.post_settings,
		size_of(Post_Settings),
	)

	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ren.post_pipeline_layout,
		0,
		1,
		&ren.desc_set_post[frame],
		0,
		nil,
	)

	vk.CmdDraw(cmd, 3, 1, 0, 0)

	imgui_impl_vulkan.RenderDrawData(imgui.GetDrawData(), cmd)
	vk.CmdEndRendering(cmd)
}

begin_frame :: proc(ren: ^Renderer) -> vk.CommandBuffer {
	profile_scoped()
	frame := ren.frame_index
	check(vk.WaitForFences(ren.device, 1, &ren.fences[frame], true, max(u64)))
	check(vk.ResetFences(ren.device, 1, &ren.fences[frame]))

	swapchain_check(
		ren,
		vk.AcquireNextImageKHR(
			ren.device,
			ren.swapchain,
			max(u64),
			ren.semaphore_image[frame],
			0,
			&ren.image_index,
		),
	)

	cmd: vk.CommandBuffer = ren.command_buffers[frame]

	vk.ResetCommandBuffer(cmd, {})

	cbi: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cbi))

	return cmd
}

end_frame :: proc(cmd: vk.CommandBuffer, ren: ^Renderer) {
	profile_scoped()
	cmd := cmd
	frame := ren.frame_index

	present_barrier: vk.ImageMemoryBarrier2 = {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {},
		oldLayout = .ATTACHMENT_OPTIMAL,
		newLayout = .PRESENT_SRC_KHR,
		image = ren.swap_images[ren.image_index].image,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}

	pdi: vk.DependencyInfo = {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &present_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &pdi)


	readback_barrier := vk.BufferMemoryBarrier2 {
		sType         = .BUFFER_MEMORY_BARRIER_2,
		srcStageMask  = {.FRAGMENT_SHADER},
		srcAccessMask = {.SHADER_STORAGE_WRITE},
		dstStageMask  = {.HOST},
		dstAccessMask = {.HOST_READ},
		buffer        = ren.picking_buffers[frame].buff,
		offset        = 0,
		size          = size_of(Picking_Data),
	}

	read_dep := vk.DependencyInfo {
		sType                    = .DEPENDENCY_INFO,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers    = &readback_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &read_dep)


	vk.EndCommandBuffer(cmd)


	wait_stages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}
	si: vk.SubmitInfo = {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &ren.semaphore_image[frame],
		pWaitDstStageMask    = &wait_stages,
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &ren.semaphore_render[ren.image_index],
	}


	check(vk.QueueSubmit(ren.gfx_q, 1, &si, ren.fences[frame]))

	ren.prev_frame = ren.frame_index
	ren.frame_index = (ren.frame_index + 1) % FIF


	pi: vk.PresentInfoKHR = {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ren.semaphore_render[ren.image_index],
		swapchainCount     = 1,
		pSwapchains        = &ren.swapchain,
		pImageIndices      = &ren.image_index,
	}

	swapchain_check(ren, vk.QueuePresentKHR(ren.gfx_q, &pi))
}

sort_hit :: proc(i, j: Picking_Hit) -> bool {
	return i.depth > j.depth
}

sort_picking_hits :: proc(ren: ^Renderer) {
	profile_scoped()
	selected := cast(^Picking_Data)ren.picking_buffers[ren.frame_index].alloc_info.pMappedData

	mem.copy(
		&ren.picking_hits.hits,
		&selected.hits,
		int(size_of(Picking_Hit) * selected.hit_count),
	)

	ren.picking_hits.hit_count = selected.hit_count

	slice.sort_by(ren.picking_hits.hits[:selected.hit_count], sort_hit)
	selected.hit_count = 0
}

draw_frame :: proc(ren: ^Renderer, win: ^Window, cam: ^Camera, s: ^Scene) {
	profile_scoped()
	ren.picking_hits.hit_count = 0
	cmd := begin_frame(ren)
	draw_forward(cmd, ren, win, cam, s)
	draw_post(cmd, ren, win)
	end_frame(cmd, ren)
	sort_picking_hits(ren)
}
