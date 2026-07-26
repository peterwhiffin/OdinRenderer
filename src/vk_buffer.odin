package main

import vma "../../odin-vma"
import "core:fmt"
import vk "vendor:vulkan"

create_buffer :: proc(
	ren: ^Renderer,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	allocation_flags: vma.AllocationCreateFlags,
) -> Buffer {
	buff: Buffer

	bci: vk.BufferCreateInfo = {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	aci: vma.AllocationCreateInfo = {
		flags = allocation_flags,
		usage = .AUTO,
	}

	check(
		vma.CreateBuffer(ren.allocator, bci, aci, &buff.buff, &buff.allocation, &buff.alloc_info),
	)

	if .SHADER_DEVICE_ADDRESS in usage {
		dai: vk.BufferDeviceAddressInfo = {
			sType  = .BUFFER_DEVICE_ADDRESS_INFO,
			buffer = buff.buff,
		}

		buff.address = vk.GetBufferDeviceAddress(ren.device, &dai)
	}

	return buff
}

create_mesh_uniform_buffer :: proc(ren: ^Renderer, mr: ^Mesh_Renderer) {
	mr.uniform_buffers = make([]Buffer, FIF)

	for buff in mr.uniform_buffers {
		buff := buff
		buff = create_buffer(
			ren,
			size_of(Mesh_Uniforms),
			{.SHADER_DEVICE_ADDRESS},
			{.HOST_ACCESS_SEQUENTIAL_WRITE, .HOST_ACCESS_ALLOW_TRANSFER_INSTEAD, .MAPPED},
		)
	}
}
