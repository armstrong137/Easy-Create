#version 460 core

// ==============================================================
// 3D 星球 shader：正交投影球面贴图 + 昼夜光照 + 自转
// 思路：把绘制区域视为单位圆，圆内每个像素反解出球面法线，
// 换算经纬度采样等距圆柱投影纹理（NASA 真实摄影），经度随
// uRotation 偏移实现自转；光照用 Lambert 漫反射造昼夜半球。
// ==============================================================

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 绘制区域尺寸（正方形）
uniform float uRotation; // 自转角（弧度，随时间累加）
uniform sampler2D uTexture; // 行星表面纹理（等距圆柱投影）

out vec4 fragColor;

const float PI = 3.14159265358979;

void main() {
  // 像素坐标 → [-1,1] 单位圆坐标（y 向下为正，与屏幕一致）
  vec2 uv = (FlutterFragCoord().xy / uSize) * 2.0 - 1.0;
  float r2 = dot(uv, uv);

  // 球体外：完全透明（星空从下面透出）
  if (r2 > 1.0) {
    fragColor = vec4(0.0);
    return;
  }

  // 正交投影下的球面法线
  vec3 n = vec3(uv.x, uv.y, sqrt(1.0 - r2));

  // 法线 → 经纬度 → 纹理坐标；经度加自转角
  float lon = atan(n.x, n.z) + uRotation;
  float lat = asin(clamp(n.y, -1.0, 1.0));
  vec2 tex = vec2(fract(lon / (2.0 * PI) + 0.5), 0.5 + lat / PI);

  vec3 color = texture(uTexture, tex).rgb;

  // 昼夜光照：光源在左上前方（屏幕 y 向下，故 y 分量取负朝上）
  vec3 lightDir = normalize(vec3(-0.5, -0.35, 0.8));
  float ndl = dot(n, lightDir);

  // 柔和晨昏线：用围绕 0 的平滑过渡替代硬 Lambert，晨昏带更宽更柔
  float day = smoothstep(-0.12, 0.32, ndl);
  float light = 0.06 + 0.94 * day; // 夜半球保留 6% 微光，轮廓不消失

  // 晨昏线暖调：过渡带（day 中段）叠一层暖橙，模拟大气散射的日出日落色
  float terminator = day * (1.0 - day); // 晨昏带最大、正午/深夜为 0
  color = color + vec3(1.0, 0.5, 0.22) * terminator * 0.5;

  vec3 lit = color * light;

  // 海面高光：识别水面（蓝多于红/绿），只在向阳面加 Blinn-Phong 镜面反射
  vec3 viewDir = vec3(0.0, 0.0, 1.0); // 正交投影视线恒为 +z
  vec3 halfDir = normalize(lightDir + viewDir);
  float ocean = smoothstep(0.02, 0.12, color.b - max(color.r, color.g));
  float spec = pow(max(dot(n, halfDir), 0.0), 64.0) * ocean * day;
  lit += vec3(0.85, 0.92, 1.0) * spec * 0.55;

  // 大气临边辉光：Fresnel 临边（n.z 小）+ 向阳侧，天蓝色薄辉
  float rim = pow(1.0 - n.z, 3.0);
  float atmo = rim * smoothstep(-0.25, 0.55, ndl);
  lit += vec3(0.35, 0.56, 1.0) * atmo * 0.65;

  // 边缘平滑：单位圆边界 1px 抗锯齿过渡
  float edge = smoothstep(1.0, 1.0 - 4.0 / uSize.x, r2);

  fragColor = vec4(lit, 1.0) * edge;
}
