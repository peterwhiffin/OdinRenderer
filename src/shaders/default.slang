struct VSInput {
	float3 Pos;
	float3 norm;
	float2 UV;
};

struct Handle64 {
	uint32_t idx;
	uint32_t gen;
};

struct Picking_Hit {
	float depth;
	Handle64 handle;
};

struct Picking_Data {
	Picking_Hit hits[4096];
	uint32_t hit_count;
};

struct per_frame_uniforms {
	float4x4 proj;
	float4x4 view;
	float4 light_dir;
	float4 light_color;
	uint32_t2 mouse_pos;
	float ambient;
};

struct entity {
	float4x4 model;
	float4x4 normal_matrix;
	float4 color;
	Handle64 handle;
};

struct VSOutput {
	float4 Pos : SV_POSITION;
	float3 Norm;
	float2 UV;
	float3 frag_pos;
	float3 viewfrag_pos;
	nointerpolation float3 cam_pos;
	nointerpolation float3 light_dir;
	nointerpolation Handle64 entity_handle;
	nointerpolation uint32_t2 mouse_pos;
};

struct push_const {
	per_frame_uniforms *pfu;
	uint32_t tex_index;
};

struct material {
	float specular_power;
};

// vk::binding(binding, set)
[[vk::binding(0, 0)]]
Texture2D<float4> tex[];

[[vk::binding(1, 0)]]
SamplerState sampler;

[[vk::binding(0, 1)]]
ConstantBuffer<entity> ebuf;

[[vk::binding(0, 2)]]
RWStructuredBuffer<Picking_Data> hit_buffer;
// [[vk::binding(1, 0)]]
// ConstantBuffer<material> materials[];

[shader("vertex")]
VSOutput vertMain(VSInput input, uniform push_const pc, uint inst: SV_InstanceID)
{
	per_frame_uniforms *pfu = pc.pfu;
	VSOutput output;
	output.Pos = mul(pfu.proj, mul(pfu.view, mul(ebuf.model, float4(input.Pos.xyz, 1.0))));
	output.Norm = mul(float3x3(ebuf.normal_matrix), input.norm);
	output.UV = input.UV;
	output.light_dir = pfu.light_dir.xyz;
	// output.frag_pos =
	output.frag_pos = mul(ebuf.model, float4(input.Pos, 1.0)).xyz;
	output.viewfrag_pos = mul(pfu.view, float4(input.Pos, 1.0)).xyz;
	output.entity_handle = ebuf.handle;
	output.mouse_pos = pfu.mouse_pos;
	return output;
}

float sd_circle(float2 v, float r)
{
	return length(v) - r;
}

[shader("fragment")]
float4 fragMain(VSOutput input, float4 frag_pos: SV_Position, uniform push_const pc)
{
	uint2 center_min = input.mouse_pos - uint2(1, 1);
	uint2 center_max = input.mouse_pos + uint2(1, 1);

	if (frag_pos.x > center_min.x && frag_pos.y > center_min.y && frag_pos.x < center_max.x &&
	    frag_pos.y < center_max.y) {
		uint32_t current_index;
		InterlockedAdd(hit_buffer[0].hit_count, 1, current_index);

		if (current_index < 4096) {
			hit_buffer[0].hits[current_index] = Picking_Hit(frag_pos.z, input.entity_handle);
		} else {
			InterlockedAdd(hit_buffer[0].hit_count, -1, current_index);
		}
	}

	float4 diffuse_color = tex[pc.tex_index].Sample(sampler, input.UV);

	if (diffuse_color.a < 0.3f)
		discard;

	diffuse_color *= ebuf.color;
	float3 ambient = diffuse_color.rgb * pc.pfu.ambient;
	float3 final_color = float3(0.0);

	float3 norm = normalize(input.Norm);
	float3 albedo = diffuse_color.rgb;
	float3 direction = normalize(-input.light_dir);
	float diff = max(dot(norm, direction), 0.0);

	final_color = albedo * pc.pfu.light_color.rgb * pc.pfu.light_color.a * diff + ambient;

	return float4(final_color.rgb, ebuf.color.a);
}

// struct Hit {
//     uint id;
//     float depth;
// };
//
// layout(binding = 0, std430) buffer HitBuffer {
//     uint hitCount;
//     Hit hits[];
// }
//
// uniform ivec2 u_selectedRegionMin;
// uniform ivec2 u_selectedRegionMax;
// uniform uint u_objectId;
//
// void main() {
//     const ivec2 fragCoord = ivec2(gl_FragCoord.xy);
//     if (all(greaterThanEqual(fragCoord, u_selectedRegionMin)) && all(lessThanEqual(fragCoord, u_selectedRegionMax))) {
//         const uint myIndex = atomicAdd(hitCount, 1);
//         if (myIndex < hits.length()) {
//             hits[myIndex] = Hit(u_objectId, gl_FragCoord.z);
//         } else {
//             atomicAdd(hitCount, -1);
//         }
//     }
// }
