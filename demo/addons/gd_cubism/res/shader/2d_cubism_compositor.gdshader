// SPDX-License-Identifier: MIT
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D backdrop : hint_screen_texture, filter_nearest;
uniform sampler2D layers : filter_nearest;
uniform int modes[512];
uniform int count;
uniform vec2 grid;

void fragment() {
    vec4 value = textureLod(backdrop, SCREEN_UV, 0.0);
    for (int i = 0; i < count; i++) {
        vec2 cell = vec2(mod(float(i), grid.x), floor(float(i) / grid.x));
        vec4 part = texture(layers, (cell + UV) / grid);
        if (modes[i] == 0) value = part + value * (1.0 - part.a);
        else if (modes[i] == 1) value.rgb += part.rgb;
        else value.rgb *= part.rgb;
        // Preserve the destination's RGBA8 saturation after each drawable,
        // including additive saturation followed by a multiply drawable.
        value = floor(clamp(value, vec4(0.0), vec4(1.0)) * 255.0 + 0.5) / 255.0;
    }
    COLOR = value;
}
