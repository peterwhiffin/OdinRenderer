package main

import "core:encoding/json"
import "core:os"
import b3 "vendor:box3d"

build_entity :: proc(
	scene: ^Scene,
	se: ^S_Entity,
	res: ^Resources,
	ren: ^Renderer,
	phys: ^Physics,
) -> ^Entity {
	eh, e := scene_get_new_entity(scene)
	e.name = se.name

	for &sc in se.children {
		ce := build_entity(scene, &sc, res, ren, phys)
		ce.parent = eh
	}

	if .TRANSFORM in se.flags {
		t := &e.transform
		st := &se.transform
		set_position(t, st.pos)
		set_euler_angles(t, st.rot)
		set_scale(t, st.scale)
	}
	if .MESH_RENDERER in se.flags {
		sm := &se.mesh_renderer
		mr := entity_add_mesh(scene, e, ren, res)
		mr.mesh = res.mesh_map[sm.mesh]
		mr.color = sm.color
	}

	if .RIGIDBODY in se.flags {
		srb := &se.rigidbody
		rb: ^Rigidbody

		#partial switch srb.shape {
		case .hullShape:
			hull := b3.MakeBoxHull(srb.shape_data[0], srb.shape_data[1], srb.shape_data[2])
			rb = entity_add_rigidbody(scene, phys, e, &hull, srb.type)
		}
	}

	return e
}

build_scene :: proc(ss: ^S_Scene, scene: ^Scene, res: ^Resources, ren: ^Renderer, phys: ^Physics) {
	for &se in ss.entities {
		build_entity(scene, &se, res, ren, phys)
	}
}

load_scene :: proc(path: cstring, scene: ^Scene, res: ^Resources, ren: ^Renderer, phys: ^Physics) {
	ss: S_Scene
	scene_init(scene)

	data, err := os.read_entire_file(string(path), context.allocator)
	defer delete(data)
	check(err)

	check(json.unmarshal(data, &ss, .Bitsquid))
	build_scene(&ss, scene, res, ren, phys)
}
