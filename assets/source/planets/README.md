# 星球源资产（source，勿直接打包进 App）

> 清单 §10 规定：所有最终资产必须能从 source 重新生成，不允许只留处理后的图。

## 源图清单与授权

| 文件 | 原生尺寸 | 来源 | 授权 |
|------|---------|------|------|
| `8k_earth_daymap.jpg` | 8192×4096 | solarsystemscope.com/textures | CC-BY 4.0 |
| `8k_mars.jpg` | 8192×4096 | 同上 | CC-BY 4.0 |
| `8k_venus_surface.jpg` | 8192×4096 | 同上（麦哲伦号雷达测绘） | CC-BY 4.0 |
| `8k_jupiter.jpg` | 4096×2048 | 同上（站点原生上限即 4K） | CC-BY 4.0 |
| `8k_saturn.jpg` | 4096×2048 | 同上（站点原生上限即 4K） | CC-BY 4.0 |
| `8k_saturn_ring_alpha.png` | 8192×500 | 同上（带 alpha，x 轴=内→外半径，含卡西尼缝） | CC-BY 4.0 |

均基于 NASA 公开数据重制。署名要求见 https://www.solarsystemscope.com/textures/

地球其余分层纹理（法线/海洋掩码/云层）来自 three.js r147 examples（MIT / 公有领域）。

## 打包产物生成（LOD 两档）

`assets/planet_scene/textures/` 下的贴图全部由本目录源图降采样而来：

- **base（常态）**：2048×1024，JPEG q88 — 首屏快，正常视距下已无可见差异
- **hi（放大 LOD）**：源图原生上限（火星/金星/地球 8192，木星/土星 4096），
  JPEG q84（金星雷达图细节密，q76 控体积）；缩放超过 `lodZoom`(1.35) 时按需换入

生成脚本（PowerShell + System.Drawing，双三次插值）：

```powershell
Add-Type -AssemblyName System.Drawing
# 例：火星 base
$img = [System.Drawing.Image]::FromFile("assets\source\planets\8k_mars.jpg")
$bmp = New-Object System.Drawing.Bitmap 2048, 1024
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.DrawImage($img, 0, 0, 2048, 1024)
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ? { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]88)
$bmp.Save("assets\planet_scene\textures\mars_2048.jpg", $enc, $ep)
```

土星环 `saturn_ring.png` 直接复制源图（63KB，带 alpha 通道不可转 JPG）。

## 与旧资产的关系

`assets/textures/{earth,mars,jupiter,venus,saturn}.jpg`（2048×1024，由用户 2D 素材
经 `tool/planet_texture_gen.dart` 反投影生成）**保留不动**，供旧 FragmentShader
星球（低端机/测试回退路径）使用。3D 场景改用本目录的 CC-BY 摄影级纹理。
