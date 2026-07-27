package main

import vma "../../odin-vma"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:path/filepath"
import stbi "vendor:stb/image"
import vk "vendor:vulkan"

import "core:strings"
import "vendor:cgltf"


load_image :: proc(
	ren: ^Renderer,
	res: ^Resources,
	new_img: ^Image,
	path: cstring,
	d: [^]byte = nil,
	w: c.int = 0,
	h: c.int = 0,
	ch: c.int = 0,
) {
	// w, h, ch: c.int
	d := d
	w := w
	h := h
	ch := ch

	loaded := false

	if d == nil {
		d = stbi.load(path, &w, &h, &ch, 4)
		loaded = true
	}

	if d == nil {
		log.errorf("Failed to load image: %s", path)
	}


	size := vk.DeviceSize(w * h * 4)
	mip_levels := math.floor(math.log2(max(f32(w), f32(h)))) + 1
	staging_buf: Buffer = create_buffer(
		ren,
		size,
		{.TRANSFER_SRC},
		{.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
	)
	defer vma.DestroyBuffer(ren.allocator, staging_buf.buff, staging_buf.allocation)

	mem.copy(staging_buf.alloc_info.pMappedData, d, int(size))
	if loaded {
		stbi.image_free(d)
	}

	new_img^ = create_image(
		ren,
		{u32(w), u32(h), 1},
		u32(mip_levels),
		{._1},
		{.TRANSFER_DST, .SAMPLED},
		.R8G8B8A8_SRGB,
		{.COLOR},
	)

	cmd := begin_one_time_cmd(ren)
	defer end_one_time_cmd(ren, cmd)

	transition_image(
		ren,
		new_img^,
		cmd,
		{},
		{},
		{.TRANSFER},
		{.TRANSFER_WRITE},
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
		u32(mip_levels),
	)

	sl: vk.ImageSubresourceLayers = {
		aspectMask     = {.COLOR},
		mipLevel       = 0,
		layerCount     = 1,
		baseArrayLayer = 0,
	}

	bic: vk.BufferImageCopy = {
		bufferOffset      = 0,
		bufferImageHeight = 0,
		imageSubresource  = sl,
		imageOffset       = {0, 0, 0},
		imageExtent       = {u32(w), u32(h), 1},
	}

	vk.CmdCopyBufferToImage(cmd, staging_buf.buff, new_img.image, .TRANSFER_DST_OPTIMAL, 1, &bic)

	transition_image(
		ren,
		new_img^,
		cmd,
		{.TRANSFER},
		{.TRANSFER_WRITE},
		{.FRAGMENT_SHADER},
		{.SHADER_READ},
		.TRANSFER_DST_OPTIMAL,
		.READ_ONLY_OPTIMAL,
		{.COLOR},
		u32(mip_levels),
	)
}

find_accessor :: proc(
	prim: ^cgltf.primitive,
	type: cgltf.attribute_type,
	index: c.int,
) -> (
	ok: b32,
	acc: ^cgltf.accessor,
) {
	for &attr in prim.attributes {
		if attr.type == type && attr.index == index {
			return true, attr.data
		}
	}

	return false, nil
}

//TODO: Apply transforms from nodes
load_gltf :: proc(
	ren: ^Renderer,
	res: ^Resources,
	new_mesh: ^Mesh,
	scale: f32,
	path: cstring,
) -> bool {
	opt: cgltf.options
	data: ^cgltf.data
	result: cgltf.result

	vert_count: u64
	ind_count: u64
	prim_count: u64
	tex_offset: u32 = res.images.count

	if data, result = cgltf.parse_file(opt, path); result != .success {
		log.errorf("Failed to Parse File: %s", path)
		cgltf.free(data)
		return false
	}

	if cgltf.validate(data) != .success {
		log.errorf("CGLTF::Failed to Validate Data: %s", path)
		cgltf.free(data)
		return false
	}

	new_mesh.submeshes = make([dynamic]Submesh)

	result = cgltf.load_buffers(opt, data, path)

	odin_str := string(path)
	dir, file := filepath.split(odin_str)
	new_mesh.name = strings.clone_to_cstring(file)

	image_indices := make(map[^cgltf.image]u32)
	defer delete(image_indices)

	image_indices[nil] = 0

	for &img, i in data.images {
		image_indices[&img] = u32(i)
		img_path, err := filepath.join({dir, string(img.uri)})
		cpath := strings.clone_to_cstring(img_path)
		new_img := get_new_image(res)
		load_image(ren, res, new_img, cpath)
		delete(cpath)
	}

	verts := make([dynamic]Vertex)
	indices := make([dynamic]u32)
	defer delete(verts)
	defer delete(indices)

	vert_offset, ind_offset: uint

	for &mesh in data.meshes {
		for &prim in mesh.primitives {
			pos_acc: ^cgltf.accessor
			pos_ok: b32
			v: Vertex

			if pos_ok, pos_acc = find_accessor(&prim, .position, 0); pos_ok {
				norm_ok, norm_acc := find_accessor(&prim, .normal, 0)
				uv_ok, uv_acc := find_accessor(&prim, .texcoord, 0)

				for i in 0 ..< pos_acc.count {
					if ok := cgltf.accessor_read_float(pos_acc, i, &v.pos[0], 3); !ok do log.warnf("Failed to read position: %s", path)

					if norm_ok {
						if ok := cgltf.accessor_read_float(norm_acc, i, &v.norm[0], 3); !ok do log.warnf("Failed to read normal: %s", path)
					}

					if uv_ok {
						if ok := cgltf.accessor_read_float(uv_acc, i, &v.uv[0], 2); !ok do log.warnf("Failed to read UV: %s", path)
					}

					v.pos *= scale
					append(&verts, v)
				}
			}

			for i in 0 ..< prim.indices.count {
				index := cgltf.accessor_read_index(prim.indices, i)
				index += vert_offset
				append(&indices, u32(index))
			}


			img: ^cgltf.image = nil
			tex_index: u32 = 0

			//TODO: Query textures correctly. no idea
			if prim.material != nil {
				if prim.material.has_pbr_metallic_roughness {
					if prim.material.pbr_metallic_roughness.base_color_texture.texture != nil {
						img =
							prim.material.pbr_metallic_roughness.base_color_texture.texture.image_
						tex_index = image_indices[img] + tex_offset
					}
				}
			}


			sm: Submesh = {
				tex_index    = tex_index,
				index_offset = ind_offset,
				index_count  = prim.indices.count,
			}

			append(&new_mesh.submeshes, sm)

			vert_offset += pos_acc.count
			ind_offset += prim.indices.count
		}
	}

	cgltf.free(data)

	vsize := size_of(Vertex) * len(verts)
	isize := size_of(u32) * len(indices)
	new_mesh.index_offset = u64(vsize)

	new_mesh.buffer = create_buffer(
		ren,
		vk.DeviceSize(vsize + isize),
		{.VERTEX_BUFFER, .INDEX_BUFFER},
		{.HOST_ACCESS_SEQUENTIAL_WRITE, .HOST_ACCESS_ALLOW_TRANSFER_INSTEAD, .MAPPED},
	)

	//TODO: figure out if this is meant to be used like this
	mapped: [^]u8 = ([^]u8)(new_mesh.buffer.alloc_info.pMappedData)
	mem.copy(mapped, raw_data(verts), vsize)
	mem.copy(mapped[vsize:], raw_data(indices), isize)

	// mdata := new_mesh.buffer.alloc_info.pMappedData
	// mem.copy(mdata, raw_data(verts), vsize)
	// mem.copy(rawptr(uintptr(mdata) + uintptr(vsize)), raw_data(indices), isize)

	return true
}


get_new_image :: proc(res: ^Resources) -> ^Image {
	img := &res.images.data[res.images.count]
	res.images.count += 1
	return img
}

get_new_mesh :: proc(res: ^Resources) -> ^Mesh {
	mesh := &res.meshes.data[res.meshes.count]
	res.meshes.count += 1
	return mesh
}

resources_init :: proc(res: ^Resources) {
	res.meshes.data = make([]Mesh, 100)
	res.images.data = make([]Image, 500)
}

load_model :: proc(ren: ^Renderer, res: ^Resources, scale: f32, path: cstring) {
	mesh := get_new_mesh(res)
	spath := string(path)
	ext := filepath.ext(spath)

	if ext == ".gltf" {
		load_gltf(ren, res, mesh, scale, path)
	}

}
