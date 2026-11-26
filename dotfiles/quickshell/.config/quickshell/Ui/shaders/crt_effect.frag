#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_intensity;
    float u_width;
    float u_height;
    float u_scanlineAlpha;
    vec4 u_accent;
};

layout(binding = 1) uniform sampler2D source;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float w = max(u_width, 1.0);
    float h = max(u_height, 1.0);
    vec2 px = vec2(uv.x * w, uv.y * h);

    // u_intensity == 0.0 -> slow living CRT look using theme accent (no glitch/flicker)
    // u_intensity > 0.0  -> brief glitch burst (segmented slices + RGB dispersion)
    float burst = clamp(u_intensity, 0.0, 1.0);
    float t = u_time;

    // 1. Short segmented horizontal slice pockets on glitch bursts
    float segX = floor(px.x / 68.0);
    float bandIdx = floor(px.y / 3.0);
    float bandRand = hash12(vec2(bandIdx, segX + floor(t * 7.5) * 13.0));
    float blockPx = (bandRand > 0.80) ? (bandRand - 0.90) * 95.0 * burst : 0.0;

    // 2. Infrequent, crisp slightly fast horizontal sweep line (~0.93s pass every ~6.7s)
    // Moves briskly top->bottom during activeWindow, then stays offscreen between passes.
    float cycle = fract(t * 0.075);
    float activeWindow = 0.14;
    float sweepActive = step(cycle, activeWindow);
    float sweepPos = mix(-0.18, 1.18, clamp(cycle / activeWindow, 0.0, 1.0));
    float sweepBar = smoothstep(0.085, 0.0, abs(uv.y - sweepPos)) * sweepActive;
    float trackPx = (hash12(vec2(floor(px.y * 0.5), segX + floor(t * 18.0))) - 0.5) * (3.5 + 11.0 * burst) * sweepBar;

    // Gentle living horizontal CRT sync hum (subtle full-time + boosted on burst)
    float syncWavePx = sin(px.y * 0.20 - t * 2.2) * (0.45 + 2.2 * burst);

    vec2 sampleUv = uv;
    sampleUv.x = clamp(uv.x + (blockPx + trackPx + syncWavePx) / w, 0.0005, 0.9995);

    // 3. Controlled chromatic aberration (subtle full-time, distinct RGB spread on bursts)
    float ambientSplitPx = 1.25 + 0.35 * sweepBar;
    float splitUvX = (ambientSplitPx + (8.5 * burst) + (7.0 * sweepBar * burst)) / w;
    float splitUvY = (1.6 * burst) / h;

    vec4 center = texture(source, sampleUv);
    vec4 leftSample = texture(source, vec2(clamp(sampleUv.x - splitUvX, 0.0005, 0.9995), clamp(sampleUv.y - splitUvY, 0.0005, 0.9995)));
    vec4 rightSample = texture(source, vec2(clamp(sampleUv.x + splitUvX, 0.0005, 0.9995), clamp(sampleUv.y + splitUvY, 0.0005, 0.9995)));

    vec3 col = vec3(leftSample.r, center.g, rightSample.b);
    float outAlpha = max(center.a, max(leftSample.a, rightSample.a) * (0.15 + 0.45 * burst));

    // Chromatic edge fringe tinted with theme accent + cool cyan counterpoint
    float edgeSpread = max(0.0, (leftSample.a + rightSample.a) * 0.5 - center.a);
    float fringeStrength = 0.10 + 0.38 * burst;
    col += u_accent.rgb * max(0.0, leftSample.a - center.a) * fringeStrength;
    col += vec3(0.28, 0.72, 0.80) * max(0.0, rightSample.a - center.a) * fringeStrength * 0.75;

    // 4. Visible HiDPI CRT scanlines (~4.5px pitch, brightness-preserving for dark themes)
    float scanWave = cos(px.y * 1.3962634);
    float scanMod = 1.0 + clamp(u_scanlineAlpha, 0.0, 0.45) * 0.38 * scanWave;
    float sweepLift = 1.0 + 0.08 * sweepBar;
    col = col * scanMod * sweepLift;

    // Accent phosphor ambience + vivid theme-accent sweep line (zero shadow crushing)
    col += u_accent.rgb * 0.045 * center.a;
    col += u_accent.rgb * (0.42 + 0.38 * burst) * sweepBar * center.a;

    // 5. Slow living CRT phosphor grain (positive-biased so dark themes stay bright)
    float fineGrain = (hash12(floor(px * 0.5) + floor(t * 9.0)) - 0.35) * (0.045 + 0.14 * burst);
    col += fineGrain * max(center.a, edgeSpread);

    fragColor = vec4(clamp(col, 0.0, 1.0), outAlpha) * qt_Opacity;
}
