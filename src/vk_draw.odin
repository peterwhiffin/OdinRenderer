package main

import imgui "../../odin-imgui"
import "../../odin-imgui/imgui_impl_sdl3"
import "../../odin-imgui/imgui_impl_vulkan"
import "core:fmt"
import "core:math/linalg"
import "core:mem"

import vk "vendor:vulkan"


draw_frame :: proc(ren: ^Renderer, win: ^Window, cam: ^Camera, s: ^Scene) {
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

	out_barrier: []vk.ImageMemoryBarrier2 = {
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
		imageView = ren.swap_images[ren.image_index].view,
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
		clearValue = {depthStencil = {depth = 1.0, stencil = 0}},
	}

	ri: vk.RenderingInfo = {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = win.w, height = win.h}},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &cai,
		pDepthAttachment = &dai,
	}

	vk.CmdBeginRendering(cmd, &ri)

	vp: vk.Viewport = {
		width    = f32(win.w),
		height   = f32(win.h),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &vp)

	sc: vk.Rect2D = {
		extent = {width = win.w, height = win.h},
	}

	vk.CmdSetScissor(cmd, 0, 1, &sc)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ren.post_pipeline)

	uni: Frame_Uniforms = {
		proj = cam.proj,
		view = cam.view,
	}

	mem.copy(ren.test_buff[frame].alloc_info.pMappedData, &uni, size_of(Frame_Uniforms))

	offset: u32 = 0
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ren.post_pipeline_layout,
		0,
		1,
		&ren.desc_set_tex,
		0,
		&offset,
	)

	for i in 0 ..< s.entities.count {
		e := &s.entities.data[i]
		if .MESH_RENDERER not_in e.flags do continue

		mr := &e.mesh_renderer
		m := mr.mesh

		voffset: vk.DeviceSize = 0
		vk.CmdBindVertexBuffers(cmd, 0, 1, &m.buffer.buff, &voffset)
		vk.CmdBindIndexBuffer(cmd, m.buffer.buff, vk.DeviceSize(m.index_offset), .UINT32)

		muni: Mesh_Uniforms = {
			model         = e.transform.world_transform,
			normal_matrix = mr.normal_matrix,
			color         = mr.color,
		}

		mem.copy(mr.uniform_buffers[frame].alloc_info.pMappedData, &muni, size_of(Mesh_Uniforms))

		vk.CmdBindDescriptorSets(
			cmd,
			.GRAPHICS,
			ren.post_pipeline_layout,
			1,
			1,
			&mr.desc_sets[frame],
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
				ren.post_pipeline_layout,
				{.FRAGMENT, .VERTEX},
				0,
				size_of(Push_Constants),
				&pc,
			)

			vk.CmdDrawIndexed(cmd, u32(sm.index_count), 1, u32(sm.index_offset), 0, 0)
		}
	}

	imgui_impl_vulkan.RenderDrawData(imgui.GetDrawData(), cmd)
	vk.CmdEndRendering(cmd)

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
