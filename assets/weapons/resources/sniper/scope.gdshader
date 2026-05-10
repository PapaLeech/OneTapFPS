shader_type canvas_item;

uniform float scope_radius : hint_range(0.1, 0.5) = 0.38;
uniform float edge_softness : hint_range(0.001, 0.05) = 0.008;
uniform float crosshair_thickness : hint_range(0.0005, 0.005) = 0.0012;
uniform float crosshair_length : hint_range(0.01, 0.15) = 0.06;
uniform float crosshair_gap : hint_range(0.0, 0.05) = 0.015;
uniform vec4 crosshair_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 scope_tint : source_color = vec4(0.05, 0.08, 0.05, 0.15);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

    float dist = length(uv);

    // Black surround outside scope circle
    float mask = smoothstep(scope_radius, scope_radius - edge_softness, dist);
    float outside = 1.0 - mask;

    // Scope edge ring
    float ring = smoothstep(scope_radius, scope_radius - edge_softness * 2.0, dist) -
                 smoothstep(scope_radius - edge_softness * 2.0, scope_radius - edge_softness * 6.0, dist);

    // Crosshair lines
    float ch = 0.0;
    // Horizontal
    if (abs(uv.y) < crosshair_thickness && abs(uv.x) > crosshair_gap && abs(uv.x) < crosshair_gap + crosshair_length) {
        ch = 1.0;
    }
    // Vertical
    if (abs(uv.x) < crosshair_thickness && abs(uv.y) > crosshair_gap && abs(uv.y) < crosshair_gap + crosshair_length) {
        ch = 1.0;
    }

    vec4 black = vec4(0.0, 0.0, 0.0, 1.0);
    vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);

    // Combine
    vec4 col = mix(transparent, black, outside);
    col = mix(col, scope_tint, mask * scope_tint.a);
    col = mix(col, crosshair_color, ch * mask);

    COLOR = col;
}
