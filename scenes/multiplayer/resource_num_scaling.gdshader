shader_type canvas_item;

uniform vec2 scale = vec2(1.0, 1.0); // Scaling factor
uniform vec2 uv_margin = vec2(0.01, 0.01); // Margin to avoid texture bleeding

void fragment() {
    // Scale the UV coordinates while keeping the texture centered
    vec2 scaled_uv = (UV - 0.5) / scale + 0.5;

    // Add a small margin to avoid sampling outside the tile's bounds
    scaled_uv = clamp(scaled_uv, uv_margin, 1.0 - uv_margin);

    // Sample the texture
    COLOR = texture(TEXTURE, scaled_uv);
}
