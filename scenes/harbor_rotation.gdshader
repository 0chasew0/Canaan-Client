shader_type canvas_item;

uniform float angle : hint_range(0.0, 360.0); // Rotation angle in degrees

void fragment() {
    // Convert the angle to radians
    float radians = radians(angle);

    // Calculate the center of the texture
    vec2 center = vec2(0.5, 0.5);

    // Move UV coordinates to the origin (center of the texture)
    vec2 rotated_uv = UV - center;

    // Apply rotation transformationrotated_uv = clamp(rotated_uv, vec2(0.0), vec2(1.0));
    rotated_uv = vec2(
        rotated_uv.x * cos(radians) - rotated_uv.y * sin(radians),
        rotated_uv.x * sin(radians) + rotated_uv.y * cos(radians)
    );

    // Move UV coordinates back to their original position
    rotated_uv += center;
	
	if (rotated_uv.x < 0.0 || rotated_uv.x > 1.0 || rotated_uv.y < 0.0 || rotated_uv.y > 1.0) {
    		COLOR = vec4(0.0, 0.0, 0.0, 0.0); // Use a fallback color (e.g., black)
	} else {
		COLOR = texture(TEXTURE, rotated_uv);
	}
	
	//COLOR = texture(TEXTURE, rotated_uv);
}
