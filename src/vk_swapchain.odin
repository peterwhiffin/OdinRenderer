package main

import vma "../../odin-vma"
import "core:c"
import "core:log"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

swapchain_check :: proc(ren: ^Renderer, result: vk.Result) {
	if result < .SUCCESS {
		if (result == .ERROR_OUT_OF_DATE_KHR) {
			ren.update_swap = true
			return
		}

		log.panic("Swapchain Error: ", result)
	} else {
		// log.warnf("Swapchain result: ", result)
	}
}

swapchain_update :: proc(ren: ^Renderer, win: ^Window) {
	if !ren.update_swap do return

	ren.update_swap = false
	w, h: c.int
	sdl.GetWindowSize(win.sdl_win, &w, &h)
	win.w, win.h = u32(w), u32(h)

	vk.DeviceWaitIdle(ren.device)
	old_swap := ren.swapchain
	old_img := ren.swap_images

	swapchain_create(ren, win, old_swap)

	for &sem in ren.semaphore_render {
		vk.DestroySemaphore(ren.device, sem, nil)
	}

	sci: vk.SemaphoreCreateInfo = {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	for &sem in ren.semaphore_render {
		vk.CreateSemaphore(ren.device, &sci, nil, &sem)
	}

	vk.DestroySwapchainKHR(ren.device, old_swap, nil)
	for img in old_img {
		vk.DestroyImageView(ren.device, img.view, nil)
	}

	vma.DestroyImage(ren.allocator, ren.depth_image.image, ren.depth_image.allocation)
	vk.DestroyImageView(ren.device, ren.depth_image.view, nil)

	create_depth_image(ren, win.w, win.h)


}

swapchain_create :: proc(ren: ^Renderer, win: ^Window, old: vk.SwapchainKHR = 0) {
	caps: vk.SurfaceCapabilitiesKHR
	extent: vk.Extent2D
	image_count: u32

	check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ren.physical, ren.surface, &caps))

	if caps.currentExtent.width == 0xFFFFFFFF {
		extent.width = win.w
		extent.height = win.h
	} else {
		extent = caps.currentExtent
	}

	ren.swap_format = .B8G8R8A8_SRGB

	sci: vk.SwapchainCreateInfoKHR = {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ren.surface,
		minImageCount    = caps.minImageCount,
		imageFormat      = ren.swap_format,
		imageColorSpace  = .SRGB_NONLINEAR,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = {.IDENTITY},
		compositeAlpha   = {.OPAQUE},
		presentMode      = .MAILBOX,
		oldSwapchain     = old,
	}

	check(vk.CreateSwapchainKHR(ren.device, &sci, nil, &ren.swapchain))
	check(vk.GetSwapchainImagesKHR(ren.device, ren.swapchain, &image_count, nil))
	ren.swap_count = image_count
	ren.swap_images = make([]Image, image_count)
	img_temp := make([]vk.Image, image_count)
	defer delete(img_temp)

	check(vk.GetSwapchainImagesKHR(ren.device, ren.swapchain, &image_count, &img_temp[0]))

	for img, i in img_temp {
		ren.swap_images[i].image = img

		sr: vk.ImageSubresourceRange = {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		}

		vci: vk.ImageViewCreateInfo = {
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = ren.swap_images[i].image,
			viewType         = .D2,
			format           = ren.swap_format,
			subresourceRange = sr,
		}

		check(vk.CreateImageView(ren.device, &vci, nil, &ren.swap_images[i].view))
	}
}
