# 一键：构建 Web 版 → 起局域网服务 → 打印手机可访问的地址
#
# 用法（项目根目录）：
#   powershell -File scripts\serve_web.ps1            # 构建 + 起服务
#   powershell -File scripts\serve_web.ps1 -SkipBuild # 只重启服务
#
# 每次改完代码跑一次，手机刷新即可看到最新效果。
param(
    [switch]$SkipBuild,
    [int]$Port = 8788
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 1. 构建 Web 版
if (-not $SkipBuild) {
    Write-Host "==> 构建 Web 版（release）…" -ForegroundColor Cyan
    & flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build web 失败" }
}
if (-not (Test-Path "build\web\index.html")) { throw "build/web 不存在，请先构建" }

# 2. 释放端口（旧服务/别的进程占着会让手机连到过期内容）
$conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    Write-Host "==> 端口 $Port 被 PID $($c.OwningProcess) 占用，停止它" -ForegroundColor Yellow
    Stop-Process -Id $c.OwningProcess -Force -Confirm:$false
}
Start-Sleep -Milliseconds 500

# 3. 防火墙放行（手机在同一 WiFi 下必须能入站；无管理员权限时提示）
$ruleName = "EasyCreateWeb体验$Port"
$exists = (netsh advfirewall firewall show rule name="$ruleName" 2>&1) -match 'Rule Name'
if (-not $exists) {
    Write-Host "==> 添加防火墙入站规则（需要管理员确认）" -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -Wait -ArgumentList `
        "-Command", "netsh advfirewall firewall add rule name=`"$ruleName`" dir=in action=allow protocol=TCP localport=$Port"
}

# 4. 起服务
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw "PATH 里找不到 dart，请把 <flutter>\bin 加入 PATH"
}
Write-Host "==> 启动服务…" -ForegroundColor Cyan
$log = Join-Path $env:TEMP "easycreate_web_serve.log"
Start-Process -FilePath "dart" -ArgumentList "run", "scripts\serve_web.dart", "$Port" `
    -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err"

# 5. 自测：环回 + 局域网地址都要通（只通环回 = 手机连不上）
# dart run 首次要跑 build hooks，可能十几秒才监听，故轮询而非固定等待
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object -First 1).IPAddress

$ok = $false
foreach ($i in 1..40) {
    Start-Sleep -Milliseconds 800
    try { $null = Invoke-WebRequest "http://127.0.0.1:$Port/" -TimeoutSec 3 -UseBasicParsing; $ok = $true; break }
    catch { }
}
if (-not $ok) { throw "服务未起来，见日志 $log" }

try { $null = Invoke-WebRequest "http://${ip}:$Port/" -TimeoutSec 8 -UseBasicParsing }
catch { Write-Host "！局域网地址不通，多半是防火墙拦了入站" -ForegroundColor Red }

# 5.5 场景功能自检（无头浏览器真实跑一遍缩放/旋转/LOD 链路）：
# 防止"改完代码后星球放不大/转不动"这类回归溜到手机上才被发现
$edge = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edge) {
    Write-Host "==> 场景功能自检（无头浏览器）…" -ForegroundColor Cyan
    $sceneUrl = "http://127.0.0.1:$Port/assets/assets/planet_scene/index.html?selftest=1" +
        "&planet=earth&spin=0&stage=1&lod=mid"
    # virtual-time-budget：快进页面里的定时器，等自检写完 <title> 再 dump。
    # 独立临时 profile：默认 profile 会命中 HTTP 缓存，测到旧构建（实测踩过）。
    # 经 cmd 包一层丢弃 stderr：PS5.1 在 EAP=Stop 下会把原生程序的任意
    # stderr 输出包装成终止性错误（Edge 启动时总打几行无害日志）
    $profile = Join-Path $env:TEMP "easycreate_selftest_profile"
    if (Test-Path $profile) { Remove-Item $profile -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
    $dom = (cmd /c "`"$edge`" --headless=new --disable-gpu --no-first-run --user-data-dir=`"$profile`" --virtual-time-budget=9000 --dump-dom `"$sceneUrl`" 2>nul") | Out-String
    if ($dom -match 'SELFTEST_PASS') {
        Write-Host "==> 场景自检 PASS（缩放 / postMessage 旋转 / LOD 换档）" -ForegroundColor Green
    } elseif ($dom -match 'SELFTEST_FAIL:([^<]+)') {
        throw "场景自检失败: $($Matches[1]) —— 缩放/旋转/换档有回归，禁止交给手机测试"
    } else {
        Write-Host "！场景自检无结论（无头浏览器未返回 title），请手动验证" -ForegroundColor Yellow
    }
} else {
    Write-Host "！未找到 Edge，跳过场景自检" -ForegroundColor Yellow
}

# 6. 报地址（IP 会随所连 WiFi/热点变化，每次以本行输出为准）
$net = (Get-NetConnectionProfile | Select-Object -First 1).Name
Write-Host ""
Write-Host "  手机 Safari 打开： http://${ip}:$Port" -ForegroundColor Green
Write-Host "  （当前网络：$net —— 手机必须连同一个）" -ForegroundColor DarkGray
Write-Host ""
