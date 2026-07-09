# 星球源资产（source，勿直接打包进 App）

> 清单 §10 规定：所有最终资产必须能从 source 重新生成，不允许只留处理后的图。

## 地球（3D 验证 Demo 与后续 P2 正式接入共用）

| 文件 | 来源 | 授权 | 用途 |
|------|------|------|------|
| `8k_earth_daymap.jpg` | solarsystemscope.com/textures（NASA 数据重制） | CC-BY 4.0（项目阶段七已采用同源素材） | 地表 albedo 源图 |

Demo 用 4K 版由本图降采样生成（PowerShell System.Drawing 双三次插值）：

```powershell
# 8K → 4K，JPEG 质量 88
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile("assets\source\planets\8k_earth_daymap.jpg")
$bmp = New-Object System.Drawing.Bitmap 4096, 2048
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, 0, 0, 4096, 2048)
# 保存为 experiments/planet_3d_demo/assets/web/textures/earth_day_4096.jpg
```

## Demo 其余纹理层（experiments/planet_3d_demo/assets/web/textures/）

| 文件 | 来源 | 授权 |
|------|------|------|
| `earth_normal_2048.jpg` 法线 | three.js r147 examples（NASA 系） | MIT/公有领域 |
| `earth_specular_2048.jpg` 海洋反射掩码 | three.js r147 examples | MIT/公有领域 |
| `earth_clouds_2048.jpg` 云层 | three.js r147 examples（PNG 转黑底 JPG，加色混合等价） | MIT/公有领域 |
| `2k_earth_nightmap.jpg` 夜光 | solarsystemscope.com/textures | CC-BY 4.0 |

P2 正式接入时按清单 §10.2 补齐每颗星球的 roughness/大气参数/LOD 分级。
