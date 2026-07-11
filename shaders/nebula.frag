#version 460 core

// 动态宇宙背景（阶段八 P2-2）：分形星云持续演变 + 程序化星场
//
// "宇宙演变快进"的实现：两级 domain-warp 的 fbm，warp 向量随时间变形
// （不是整幅平移），星云的形态、浓淡、旋涡在几十秒尺度上持续重组；
// 三层星云色（深空紫 / 星际蓝青 / 暗红尘埃心）按噪声场交融。
// uEnergy（创作能量 0~1）驱动整体亮度与星云"心部"的炽亮。

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;    // 画布尺寸（逻辑像素）
uniform float uTime;   // 秒
uniform float uEnergy; // 创作能量 0~1
uniform float uEvolve; // 演化速度倍率（全局创作量驱动，越写越"快进"）

out vec4 fragColor;

// ---------- 基础噪声 ----------
float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4 阶分形噪声：移动端全屏 shader 长期运行，5 阶在高像素比下会明显抢 GPU。
const int kFbmOctaves = 4;
float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  mat2 rot = mat2(1.6, 1.2, -1.2, 1.6);
  for (int i = 0; i < kFbmOctaves; i++) {
    v += amp * vnoise(p);
    p = rot * p;
    amp *= 0.55;
  }
  return v;
}

// ---------- 程序化星场：一格最多一颗，带各自相位的闪烁 ----------
float starLayer(vec2 p, float density, float seedShift, float t) {
  vec2 cell = floor(p * density);
  vec2 f = fract(p * density) - 0.5;
  float h = hash21(cell + seedShift);
  // 只有少数格子有星（h 越接近 1 星越亮）
  if (h < 0.90) return 0.0;
  vec2 off = vec2(hash21(cell + seedShift + 1.7), hash21(cell + seedShift + 3.1)) - 0.5;
  float d = length(f - off * 0.72);
  float tw = 0.6 + 0.4 * sin(t * (1.2 + h * 2.6) + h * 43.0);
  float core = smoothstep(0.07, 0.0, d);
  return core * tw * (h - 0.90) * 10.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = (frag - 0.5 * uSize) / uSize.y; // 居中、按高归一
  // 演化速度 = 基准 × 全局创作量倍率（空宇宙冷寂缓慢，创作旺盛时快进）
  float t = uTime * 0.018 * uEvolve;

  // ---------- 两级 domain warp：星云形态持续重组 ----------
  vec2 q = vec2(
    fbm(p * 1.7 + vec2(0.0, t)),
    fbm(p * 1.7 + vec2(5.2, -t * 1.31))
  );
  vec2 r = vec2(
    fbm(p * 1.7 + 2.8 * q + vec2(1.7, 9.2) + t * 0.62),
    fbm(p * 1.7 + 2.8 * q + vec2(8.3, 2.8) - t * 0.47)
  );
  float f = fbm(p * 1.7 + 2.4 * r);

  // ---------- 三层星云色交融 ----------
  vec3 col = vec3(0.015, 0.016, 0.045);                    // 深空底
  col = mix(col, vec3(0.10, 0.065, 0.23), smoothstep(0.32, 0.78, f));          // 紫云
  col = mix(col, vec3(0.05, 0.14, 0.25), smoothstep(0.35, 0.92, length(q)) * 0.72); // 蓝青
  col = mix(col, vec3(0.23, 0.085, 0.06), smoothstep(0.52, 0.95, r.x) * 0.55);      // 暗红尘埃
  // 能量联动：整体亮度 + 星云心部炽亮
  col *= 0.72 + 0.78 * uEnergy;
  col += vec3(0.95, 0.78, 0.62) * pow(max(f - 0.70, 0.0), 2.1) * 2.4 * (0.35 + 0.65 * uEnergy);

  // ---------- 星场三层：密度/速度不同 = 视差；能量越高星越密亮 ----------
  float starAmp = 0.75 + 0.45 * uEnergy;
  col += vec3(1.0) * starLayer(p + vec2(t * 0.010, 0.0), 22.0, 0.0, uTime) * 0.55 * starAmp;
  col += vec3(0.95, 0.97, 1.0) * starLayer(p + vec2(t * 0.024, 0.0), 12.0, 7.0, uTime) * 0.85 * starAmp;
  col += vec3(1.0, 0.96, 0.90) * starLayer(p + vec2(t * 0.045, 0.0), 6.0, 13.0, uTime) * 1.1 * starAmp;

  // ---------- 暗角：视线聚焦中央 ----------
  col *= 1.0 - 0.42 * dot(p, p);

  fragColor = vec4(col, 1.0);
}
