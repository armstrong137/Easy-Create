# 一键启动模拟器并加载 Easy Create（小说家 App）
# 流程：启动/复用模拟器 → 等开机 → 窗口居中 → 构建安装 → 启动应用
#
# 注意：不要设 $ErrorActionPreference='Stop'——adb/emulator 首次运行会往 stderr
# 打印 "daemon not running; starting now" 之类正常信息，被 Stop 当成致命错误会
# 误中断脚本（表现为莫名其妙的报错）。这里改为显式判错。

# ---- 路径与常量（如本机安装位置不同，改这里）----
$Sdk      = "$env:LOCALAPPDATA\Android\Sdk"
$Emulator = Join-Path $Sdk 'emulator\emulator.exe'
$Adb      = Join-Path $Sdk 'platform-tools\adb.exe'
$Flutter  = 'C:\src\flutter\bin\flutter.bat'
$Avd      = 'novel_test'
$Pkg      = 'com.easycreate.novel_app'
$Proj     = Split-Path -Parent $PSScriptRoot                 # 项目根 = scripts 的上级
$Apk      = Join-Path $Proj 'build\app\outputs\flutter-apk\app-debug.apk'

function Log($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "[错误] $m" -ForegroundColor Red; exit 1 }

# ---- 0. 校验工具路径 ----
if (-not (Test-Path $Adb))      { Die "找不到 adb：$Adb`n请确认 Android SDK 装在 $Sdk，或改本脚本顶部 `$Sdk 变量" }
if (-not (Test-Path $Emulator)) { Die "找不到 emulator：$Emulator" }
if (-not (Test-Path $Flutter))  { Die "找不到 flutter：$Flutter，请改本脚本顶部 `$Flutter 变量" }

# 让 flutter 等子进程也能找到 adb/emulator
$env:Path = "$(Split-Path $Adb);$(Split-Path $Emulator);$env:Path"

# 预热 adb 服务（吞掉首次 daemon 提示，避免后续调用被误判为错误）
& $Adb start-server 2>$null | Out-Null

# ---- 1. 确保模拟器在线（已运行则复用）----
$online = & $Adb devices 2>$null | Select-String -Pattern 'emulator-\d+\s+device'
if (-not $online) {
  Log "启动模拟器 $Avd ..."
  # -gpu swiftshader_indirect：带窗口时用主机 GPU 会黑屏/ANR，软渲染稳
  Start-Process -FilePath $Emulator `
    -ArgumentList '-avd', $Avd, '-gpu', 'swiftshader_indirect', '-no-boot-anim'
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
if (-not $booted) { Die "模拟器开机超时" }
Log "模拟器已就绪"

# ---- 3. 窗口居中 ----
# 用 -MemberDefinition（自动引入 System / InteropServices，无需 using 行）
Add-Type -Name Win -Namespace Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
public struct RECT { public int L,T,R,B; }
'@
Start-Sleep -Seconds 2   # 给窗口一点时间出现
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
if ($LASTEXITCODE -ne 0) { Die "构建失败，请看上方 Flutter 输出" }
if (-not (Test-Path $Apk)) { Die "未找到构建产物：$Apk" }
Log "安装到模拟器 ..."
& $Adb install -r "$Apk" 2>$null

# ---- 5. 启动应用 ----
Log "启动应用 ..."
& $Adb shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
Log "完成：模拟器已居中、应用已加载"
