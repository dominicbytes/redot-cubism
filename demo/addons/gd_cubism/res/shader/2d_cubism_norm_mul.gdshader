// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
// GDCubism shader: Mul
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform bool premultiplied_alpha = false;
uniform vec4 color_base : source_color;
uniform vec4 color_screen : source_color;
uniform vec4 color_multiply : source_color;
uniform vec4 channel : source_color;
uniform sampler2D tex_main : filter_linear_mipmap;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
    vec4 color_tex = texture(tex_main, UV);
    color_tex.rgb = color_tex.rgb * color_multiply.rgb;

    // Screen color follows the sampled texture alpha representation.
    float screen_alpha = premultiplied_alpha ? color_tex.a : 1.0;
    color_tex.rgb = (color_tex.rgb + color_screen.rgb * screen_alpha) - (color_tex.rgb * color_screen.rgb);
    vec4 color = color_tex * color_base * modulate;
    color.rgb *= premultiplied_alpha ? modulate.a : color.a;
    COLOR = vec4(color.rgb + vec3(1.0 - color.a), 1.0);
}
