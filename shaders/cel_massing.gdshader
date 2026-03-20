shader_type canvas_item;

uniform float shade_steps : hint_range(2.0, 8.0, 1.0) = 4.0;
uniform float shade_contrast : hint_range(0.8, 1.6, 0.01) = 1.08;
uniform vec3 shadow_tint : source_color = vec3(0.88, 0.84, 0.92);
uniform float band_mix : hint_range(0.0, 1.0, 0.01) = 0.7;

void fragment() {
	vec3 base = COLOR.rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	float steps = max(shade_steps, 2.0);
	float quantized = floor(lum * steps) / max(steps - 1.0, 1.0);
	float shade = mix(lum, quantized, band_mix);
	vec3 cel = base * (0.58 + shade * 0.62);
	cel = mix(cel, cel * shadow_tint, smoothstep(0.0, 0.5, 1.0 - lum) * 0.35);
	cel = pow(max(cel, vec3(0.0)), vec3(1.0 / shade_contrast));
	COLOR = vec4(cel, COLOR.a);
}
