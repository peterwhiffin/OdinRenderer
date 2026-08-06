package main

import "core:encoding/json"
import "core:os"
import "core:strings"
import b3 "vendor:box3d"

build_entity :: proc(
	scene: ^Scene,
	se: ^S_Entity,
	res: ^Resources,
	ren: ^Renderer,
	phys: ^Physics,
	win: ^Window,
) -> ^Entity {
	eh, e := scene_get_new_entity(scene)
	// delete(e.name)
	e.name = strings.clone(se.name)

	for &sc in se.children {
		ce := build_entity(scene, &sc, res, ren, phys, win)
		ce.parent = eh
	}

	if .Transform in se.flags {
		t := &e.transform
		st := &se.transform
		set_position(t, st.pos, scene)
		set_euler_angles(t, st.rot, scene)
		set_scale(t, st.scale, scene)
	}
	if .Mesh_Renderer in se.flags {
		sm := &se.mesh_renderer
		mr := entity_add_mesh(scene, e, ren, res)
		mr.mesh = res.mesh_map[sm.mesh]
		mr.color = sm.color
	}

	if .Rigidbody in se.flags {
		srb := &se.rigidbody
		rb: ^Rigidbody

		#partial switch srb.shape {
		case .hullShape:
			hull := b3.MakeBoxHull(srb.shape_data[0], srb.shape_data[1], srb.shape_data[2])
			rb = entity_add_rigidbody(scene, phys, e, &hull, srb.type)
		case .capsuleShape:
			capsule: b3.Capsule = {
				center1 = {srb.shape_data[0], srb.shape_data[1], srb.shape_data[2]},
				center2 = {srb.shape_data[3], srb.shape_data[4], srb.shape_data[5]},
				radius  = srb.shape_data[6],
			}
			rb = entity_add_rigidbody(scene, phys, e, &capsule, srb.type)
		}
	}

	if .Camera in se.flags {
		scam := &se.camera
		cam := entity_add_camera(e, win)
		cam.fov = scam.fov
		cam.near = scam.near
		cam.far = scam.far
	}

	return e
}

build_scene :: proc(
	ss: ^S_Scene,
	scene: ^Scene,
	res: ^Resources,
	ren: ^Renderer,
	phys: ^Physics,
	win: ^Window,
) {
	scene.name = strings.clone(ss.name)
	for &se in ss.entities {
		build_entity(scene, &se, res, ren, phys, win)
	}
}

load_scene :: proc(
	path: cstring,
	scene: ^Scene,
	res: ^Resources,
	ren: ^Renderer,
	phys: ^Physics,
	win: ^Window,
) {
	profile_scoped()
	ss: S_Scene
	scene_init(scene)

	data, err := os.read_entire_file(string(path), context.temp_allocator)
	check(err)

	check(json.unmarshal(data, &ss, .Bitsquid, context.temp_allocator))
	build_scene(&ss, scene, res, ren, phys, win)
}
