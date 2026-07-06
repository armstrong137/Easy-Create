# 一键启动模拟器并加载 Easy Create（小说家 App）
# 流程：自动定位工具 → 启动/复用模拟器 → 等开机 → 窗口居中 → 构建安装 → 启动应用
#
# 关键：工具路径自动发现（多候选 + 去空格 + PATH 兜底），不死信单一环境变量；
# 不设 $ErrorActionPreference='Stop'（adb/emulator 首次 stderr 会被误判为致命错误）。

$Avd  = 'novel_test'
$Pkg  = 'com.easycreate.novel_app'
$Proj = Split-Path -Parent $PSScriptRoot
$Apk  = Join-Path $Proj 'build\app\outputs\flutter-apk\app-debug.apk'

function Log($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# 从候选列表里取第一个真实存在的（去首尾空格、用 LiteralPath 避开通配符/空格坑）
function Get-FirstExisting([string[]]$paths) {
  foreach ($p in $paths) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $t = $p.Trim()
    if (Test-Path -LiteralPath $t) { return (Resolve-Path -LiteralPath $t).Path }
  }
  return $null
}

# ---- 0. 自动定位 adb / emulator / flutter ----
$adbCandidates = @(
  "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
  "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
  "$env:ANDROID_HOME\platform-tools\adb.exe",
  "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
  "$env:ProgramFiles\Android\android-sdk\platform-tools\adb.exe",
  "${env:ProgramFiles(x86)}\Android\android-sdk\platform-tools\adb.exe"
)
$Adb = Get-FirstExisting $adbCandidates
if (-not $Adb) { $c = Get-Command adb -ErrorAction SilentlyContinue; if ($c) { $Adb = $c.Source } }
if (-not $Adb) {
  Write-Host "[错误] 找不到 adb.exe。已尝试以下位置：" -ForegroundColor Red
  $adbCandidates | ForEach-Object { Write-Host "    $_" }
  Write-Host "LOCALAPPDATA=[$env:LOCALAPPDATA]  USERPROFILE=[$env:USERPROFILE]" -ForegroundColor Yellow
  Write-Host "请把 SDK 的 platform-tools 目录加入 PATH，或设置 ANDROID_HOME 环境变量后重试。" -ForegroundColor Yellow
  exit 1
}
Log "adb: $Adb"

# SDK 根 = adb 的上上级；emulator 据此定位
$Sdk = Split-Path -Parent (Split-Path -Parent $Adb)
$Emulator = Get-FirstExisting @("$Sdk\emulator\emulator.exe")
if (-not $Emulator) { $c = Get-Command emulator -ErrorAction SilentlyContinue; if ($c) { $Emulator = $c.Source } }
if (-not $Emulator) { Write-Host "[错误] 找不到 emulator.exe：$Sdk\emulator\emulator.exe" -ForegroundColor Red; exit 1 }

# flutter：PATH 优先，再退到常见安装位置
$c = Get-Command flutter -ErrorAction SilentlyContinue
if ($c) { $Flutter = $c.Source }
else { $Flutter = Get-FirstExisting @("C:\src\flutter\bin\flutter.bat", "$env:FLUTTER_ROOT\bin\flutter.bat", "$env:LOCALAPPDATA\flutter\bin\flutter.bat") }
if (-not $Flutter) { Write-Host "[错误] 找不到 flutter：不在 PATH，也不在 C:\src\flutter\bin。请把 flutter\bin 加入 PATH。" -ForegroundColor Red; exit 1 }
Log "flutter: $Flutter"

# 工具目录进 PATH，供 flutter 子进程找 adb/emulator
$env:Path = "$(Split-Path $Adb);$(Split-Path $Emulator);$env:Path"

# 预热 adb 服务（吞掉首次 daemon 提示，避免后续调用被误判）
& $Adb start-server 2>$null | Out-Null

# ---- 1. 确保模拟器在线（已运行则复用）----
$online = & $Adb devices 2>$null | Select-String -Pattern 'emulator-\d+\s+device'
if (-not $online) {
  Log "启动模拟器 $Avd ..."
  # -gpu swiftshader_indirect：带窗口时用主机 GPU 会黑屏/ANR，软渲染稳
  Start-Process -FilePath $Emulator -ArgumentList '-avd', $Avd, '-gpu', 'swiftshader_indirect', '-no-boot-anim'
} else {
  Log "检测到模拟器已在运行，复用"
}

# ---- 2. 等开机完成 ----
Log "等待模拟器开机（最多 ~3 分钟）..."
& $Adb wait-for-device 2>$null
$booted = $false
for ($i = 0; $i -lt 90; $i++) {
  $b = (& $Adb shell getprop sys.boot_completed 2>$null | Out-String).Trim()
  if ($b -eq '1') { $booted = $true; break }
  Start-Sleep -Seconds 2
}
if (-not $booted) { Write-Host "[错误] 模拟器开机超时" -ForegroundColor Red; exit 1 }
Log "模拟器已就绪"

# ---- 3. 窗口居中 ----
Add-Type -Name Win -Namespace Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
public struct RECT { public int L,T,R,B; }
'@
Start-Sleep -Seconds 2
$sw = [Native.Win]::GetSystemMetrics(0); $sh = [Native.Win]::GetSystemMetrics(1)
$proc = Get-Process |
  Where-Object { $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -match 'Android Emulator' -or $_.MainWindowTitle -match $Avd) } |
  Select-Object -First 1
if ($proc) {
  $r = New-Object Native.Win+RECT
  [Native.Win]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
  $w = $r.R - $r.L; $h = $r.B - $r.T
  $x = [int](($sw - $w) / 2); $y = [int](($sh - $h) / 2); if ($y -lt 0) { $y = 0 }
  [Native.Win]::MoveWindow($proc.MainWindowHandle, $x, $y, $w, $h, $true) | Out-Null
  Log "已居中窗口：$x,$y（${w}x${h}），屏幕 ${sw}x${sh}"
} else {
  Log "未找到模拟器窗口，跳过居中"
}

# ---- 4. 构建并安装最新代码 ----
Log "构建 Debug APK（无改动时增量很快）..."
& $Flutter build apk --debug
if ($LASTEXITCODE -ne 0) { Write-Host "[错误] 构建失败，请看上方 Flutter 输出" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $Apk)) { Write-Host "[错误] 未找到构建产物：$Apk" -ForegroundColor Red; exit 1 }
Log "安装到模拟器 ..."
& $Adb install -r "$Apk" 2>$null

# ---- 5. 启动应用 ----
Log "启动应用 ..."
& $Adb shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
Log "完成：模拟器已居中、应用已加载"
