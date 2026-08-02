package main

import hm "core:container/handle_map"
import "core:encoding/json"
import "core:os"
import "core:strings"
import b3 "vendor:box3d"

S_Scene :: struct {
	name:     string,
	entities: [dynamic]S_Entity,
}

S_Entity :: struct {
	name:          string,
	children:      [dynamic]S_Entity,
	flags:         Entity_Flags,
	transform:     S_Transform,
	mesh_renderer: S_Mesh_Renderer,
	rigidbody:     S_Rigidbody,
	camera:        S_Camera,
}

S_Transform :: struct {
	pos:   [3]f32,
	rot:   [3]f32,
	scale: [3]f32,
}

S_Mesh_Renderer :: struct {
	mesh:  string,
	color: [4]f32,
}

Shape_Data :: union {
	b3.Sphere,
	b3.Capsule,
	[3]f32,
}

S_Rigidbody :: struct {
	shape:      b3.ShapeType,
	shape_data: [7]f32,
	type:       b3.BodyType,
}

S_Camera :: struct {
	fov:  f32,
	near: f32,
	far:  f32,
}

get_s_transform :: proc(entity: ^Entity) -> S_Transform {
	t := entity.transform
	st := S_Transform {
		pos   = t.pos,
		rot   = t.euler_angles,
		scale = t.scale,
	}

	return st
}

get_s_mesh_renderer :: proc(entity: ^Entity) -> S_Mesh_Renderer {
	m := entity.mesh_renderer

	sm := S_Mesh_Renderer {
		mesh  = m.mesh.name,
		color = m.color,
	}

	return sm
}

get_s_rigidbody :: proc(entity: ^Entity) -> S_Rigidbody {
	rb := entity.rigidbody

	shape_type := b3.Shape_GetType(rb.shape_id)
	shape_data: [7]f32
	body_type := b3.Body_GetType(rb.body_id)

	#partial switch shape_type {
	case .sphereShape:
		ss := b3.Shape_GetSphere(rb.shape_id)
		shape_data[0] = ss.center.x
		shape_data[1] = ss.center.y
		shape_data[2] = ss.center.z
		shape_data[3] = ss.radius

	case .capsuleShape:
		cs := b3.Shape_GetCapsule(rb.shape_id)
		shape_data[0] = cs.center1.x
		shape_data[1] = cs.center1.y
		shape_data[2] = cs.center1.z
		shape_data[3] = cs.center2.x
		shape_data[4] = cs.center2.y
		shape_data[5] = cs.center2.z
		shape_data[6] = cs.radius
	case .hullShape:
		hull_shape := b3.Shape_GetHull(rb.shape_id)
		hs := (hull_shape.aabb.upperBound - hull_shape.aabb.lowerBound) / 2.0
		shape_data.xyz = hs.xyz
	}

	srb := S_Rigidbody {
		shape      = shape_type,
		shape_data = shape_data,
		type       = body_type,
	}

	return srb
}

get_s_camera :: proc(entity: ^Entity) -> S_Camera {
	c := entity.camera

	sc := S_Camera {
		fov  = c.fov,
		near = c.near,
		far  = c.far,
	}

	return sc
}

get_s_entity :: proc(entity: ^Entity, scene: ^Scene) -> S_Entity {
	se: S_Entity
	se.children = make([dynamic]S_Entity, context.temp_allocator)
	se.name = string(entity.name)

	se.flags = entity.flags

	for child in entity.children {
		e := hm.get(&scene.entities, child)
		append(&se.children, get_s_entity(e, scene))
	}

	if .TRANSFORM in entity.flags {
		se.transform = get_s_transform(entity)
	}

	if .MESH_RENDERER in entity.flags {
		se.mesh_renderer = get_s_mesh_renderer(entity)
	}

	if .RIGIDBODY in entity.flags {
		se.rigidbody = get_s_rigidbody(entity)
	}

	if .CAMERA in entity.flags {
		se.camera = get_s_camera(entity)
	}

	return se
}

build_s_scene :: proc(scene: ^Scene) -> S_Scene {
	s: S_Scene
	s.entities = make([dynamic]S_Entity, context.temp_allocator)
	s.name = scene.name

	it := hm.iterator_make(&scene.entities)

	for e, h in hm.iterate(&it) {
		if hm.is_valid(&scene.entities, e.parent) {
			continue
		}

		append(&s.entities, get_s_entity(e, scene))
	}

	return s
}

write_scene :: proc(scene: ^Scene) {
	merr: json.Marshal_Error
	werr: os.Error
	data: []byte
	opt: json.Marshal_Options = {
		spec                      = .Bitsquid,
		pretty                    = true,
		mjson_keys_use_equal_sign = true,
		use_enum_names            = true,
	}

	sw := build_s_scene(scene)

	data, merr = json.marshal(sw, opt)
	defer delete(data)
	check(merr)

	check(os.write_entire_file("tempscene.scene", data), "Writing Temp Scene")
	fp := strings.concatenate({scene.name, ".scene"}, context.temp_allocator)
	check(os.copy_file(fp, "tempscene.scene"), "Writing Scene")
}
