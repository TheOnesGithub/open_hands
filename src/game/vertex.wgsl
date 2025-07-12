struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
}

@vertex
fn vs_main(@location(0) in_vert_pos: vec3<f32>, @location(1) in_tex_coords: vec2<f32>) -> VertexOutput {
    var out: VertexOutput;
    out.position = vec4<f32>(in_vert_pos, 1.0);
    out.tex_coords = in_tex_coords;
    return out;
}
