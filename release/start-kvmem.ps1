# ============================================================================
#  KVMem + ROCmFP4 + DFlash2 启动器（自动扫描版）
#
#  最简单的用法：把模型丢进 models\ 目录，然后双击 start-kvmem.bat
#
#  脚本会自动：
#    1) 扫描 models\ 目录，识别「主模型 / DFlash2 草稿 / 视觉投影器」
#    2) 自动组合最优配置（有 DFlash2 就用 DFlash2，否则退 MTP，再否则关加速）
#    3) 没有模型时，打印下载清单和链接后退出
#
#  常用参数（都可省略）：
#     -ModelsDir <目录>     模型目录（默认 .\models）
#     -Model <文件>         手动指定主模型
#     -Draft <文件>         手动指定 DFlash2 草稿模型
#     -Spec auto|dflash|mtp|none   加速方式（默认 auto）
#     -List                 只列出扫描结果，不启动
#     -DryRun               只打印将执行的命令，不启动
# ============================================================================
[CmdletBinding()]
param(
    [string]$ModelsDir = '',
    [string]$Model     = '',
    [string]$Draft     = '',
    [string]$Mmproj    = '',
    [ValidateSet('auto','dflash','mtp','none')][string]$Spec = 'auto',
    [int]$Context      = 262144,
    [int]$Budget       = 36864,
    [int]$Reserve      = 32768,
    [int]$MaxTokens    = 16384,
    [int]$DraftTokens  = 3,
    [string]$KvDtype   = 'q8_0',
    [string]$Device    = 'ROCm0',
    [int]$Port         = 18200,
    [string]$HostAddress = '127.0.0.1',
    [switch]$NoWebui,
    [switch]$List,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe   = Join-Path $root 'bin/llama-kvmem-server.exe'
$uiDir = Join-Path $root 'share/kvmem/ui'
if (-not $ModelsDir) { $ModelsDir = Join-Path $root 'models' }

function Format-Size([long]$b) {
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    return ('{0:N0} KB' -f ($b / 1KB))
}

function Show-DownloadHelp {
    param([string[]]$Missing)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host '   [!] 没有找到可用的模型' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  请把下载好的 .gguf 文件放到这个目录：' -ForegroundColor White
    Write-Host "      $ModelsDir" -ForegroundColor Cyan
    Write-Host ''
    if ($Missing -contains 'main') {
        Write-Host '  【必需】主模型（二选一）' -ForegroundColor White
        Write-Host '    1) 推荐：速度最快，配合 DFlash2' -ForegroundColor Green
        Write-Host '       Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf' -ForegroundColor Cyan
        Write-Host '       来源：ROCmFP4 项目的量化产物' -ForegroundColor Gray
        Write-Host '             https://github.com/charlie12345/rocmfp4-llama' -ForegroundColor DarkGray
        Write-Host '    2) 备选：KVMem 官方配方，自带 MTP 头' -ForegroundColor Green
        Write-Host '       Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf     （11.29 GB）' -ForegroundColor Cyan
        Write-Host '       下载：https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF' -ForegroundColor DarkGray
    }
    if ($Missing -contains 'draft') {
        Write-Host ''
        Write-Host '  【推荐】DFlash2 草稿模型（实测再快 24%）' -ForegroundColor White
        Write-Host '       Qwen3.8-27B-DFlash2-Q4_K_M.gguf       （1.06 GB）' -ForegroundColor Cyan
        Write-Host '       下载：https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF' -ForegroundColor DarkGray
        Write-Host '       国内镜像：https://hf-mirror.com/incoai/Qwen3.8-27B-DFlash2-GGUF' -ForegroundColor DarkGray
    }
    if ($Missing -contains 'mmproj') {
        Write-Host ''
        Write-Host '  【可选】视觉投影器（要输入图片时才需要）' -ForegroundColor White
        Write-Host '       mmproj-Qwen3.8-27B-BF16.gguf' -ForegroundColor Cyan
        Write-Host '       下载：https://huggingface.co/HermiHg/Qwen3.8-27B-mmproj-Q5_K-MIX-GGUF' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  放好之后重新运行本脚本即可（会自动识别）。' -ForegroundColor White
    Write-Host '  也可指定其他目录：  start-kvmem.bat -ModelsDir "D:\models"' -ForegroundColor DarkGray
    Write-Host ''
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '   KVMem + ROCmFP4 + DFlash2' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host "   模型目录: $ModelsDir" -ForegroundColor Gray

if (-not (Test-Path $exe)) { throw '找不到 bin\llama-kvmem-server.exe —— 请确认 ZIP 解压完整' }
if (-not (Test-Path $ModelsDir)) {
    New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null
    Write-Host '   （该目录不存在，已自动创建）' -ForegroundColor Gray
}

# ---------------------------------------------------------------- 扫描 ----
$all     = @(Get-ChildItem $ModelsDir -Filter *.gguf -File -Recurse -ErrorAction SilentlyContinue)
$nMmproj = @($all | Where-Object { $_.Name -match 'mmproj|projector|vision' })
$nDraft  = @($all | Where-Object { ($_.Name -match 'dflash|eagle|draft') -or ($_.Name -match '^mtp[-_]') } | Where-Object { $_.Name -notmatch 'mmproj|projector|vision' })
$nMain   = @($all | Where-Object { $_.Name -notmatch 'mmproj|projector|vision|dflash|eagle|draft' -and $_.Name -notmatch '^mtp[-_]' })

function Pick-Main($list) {
    foreach ($pat in @('*ROCMFP4*','*rocmfp4*','*IQ3_S-mtp*','*IQ3*mpt*','*IQ3*','*27B*','*')) {
        $hit = $list | Where-Object { $_.Name -like $pat } | Sort-Object Length -Descending | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

$pickMain   = if ($Model)  { Get-Item $Model  -ErrorAction SilentlyContinue } else { Pick-Main $nMain }
# 草稿模型：优先 DFlash2（取体积最小的，通常是 Q4_K_M，最快）
$pickDraft  = if ($Draft)  { Get-Item $Draft  -ErrorAction SilentlyContinue } else {
    $d = $nDraft | Where-Object { $_.Name -match 'dflash' } | Sort-Object Length | Select-Object -First 1
    if (-not $d) { $d = $nDraft | Sort-Object Length | Select-Object -First 1 }
    $d
}
$pickMmproj = if ($Mmproj) { Get-Item $Mmproj -ErrorAction SilentlyContinue } else { $nMmproj | Sort-Object Length -Descending | Select-Object -First 1 }

Write-Host ''
Write-Host '   扫描结果:' -ForegroundColor White
if ($all.Count -eq 0) {
    Write-Host '      （目录里没有任何 .gguf 文件）' -ForegroundColor Yellow
} else {
    $chosen = @()
    if ($pickMain)   { $chosen += $pickMain.FullName }
    if ($pickDraft)  { $chosen += $pickDraft.FullName }
    if ($pickMmproj) { $chosen += $pickMmproj.FullName }
    foreach ($f in $all) {
        $kind = if ($f.Name -match 'mmproj|projector|vision') { '视觉投影  ' }
                elseif ($f.Name -match 'dflash|eagle|draft') { 'DFlash2草稿' }
                elseif ($f.Name -match '^mtp[-_]') { 'MTP草稿   ' }
                else { '主模型    ' }
        $mark = if ($chosen -contains $f.FullName) { '  <- 选用' } else { '' }
        Write-Host ("      [{0}] {1}  ({2}){3}" -f $kind, $f.Name, (Format-Size $f.Length), $mark) -ForegroundColor Gray
    }
}

$missing = @()
if (-not $pickMain)   { $missing += 'main' }
if (-not $pickDraft)  { $missing += 'draft' }
if (-not $pickMmproj) { $missing += 'mmproj' }

if (-not $pickMain) {
    Show-DownloadHelp -Missing $missing
    exit 1
}
if ($List) {
    Write-Host ''
    Write-Host '   （-List 模式：只列出结果，不启动服务）' -ForegroundColor Gray
    Write-Host ''
    exit 0
}

# ---------------------------------------------------------- 加速方式 ----
$hasDraft   = $null -ne $pickDraft
$mainHasMtp = $pickMain.Name -match '\-mtp|mtp\-'
$effectiveSpec = $Spec
$notice = @()
switch ($Spec) {
    'auto' {
        if ($hasDraft)        { $effectiveSpec = 'dflash' }
        elseif ($mainHasMtp)  { $effectiveSpec = 'mtp';  $notice += '未找到 DFlash2 草稿模型，自动改用主模型自带的 MTP 加速' }
        else                  { $effectiveSpec = 'none'; $notice += '未找到 DFlash2 草稿模型，且主模型不含 MTP 头，已关闭推测解码' }
    }
    'dflash' {
        if (-not $hasDraft) {
            $notice += '指定了 dflash 但没找到草稿模型，已自动降级'
            if ($mainHasMtp) { $effectiveSpec = 'mtp';  $notice += '-> 改用 MTP' }
            else             { $effectiveSpec = 'none'; $notice += '-> 关闭推测解码' }
        }
    }
    'mtp' {
        if (-not $mainHasMtp) { $notice += '主模型文件名不含 -mtp，可能没有内置 MTP 头；若启动失败请改用 -Spec none' }
    }
}

# ---------------------------------------------------------------- 拼参数 ----
$exeArgs = @(
    '-m', $pickMain.FullName
    '--device', $Device, '-ngl', '99', '--load-mode', 'none'
    '--host', $HostAddress, '--port', "$Port"
    '-c', "$Context", '-b', '512', '-n', "$MaxTokens"
    '--kvmem', '--kvmem-budget', "$Budget", '--kvmem-gen-reserve', "$Reserve"
    '--kv-dtype', $KvDtype
    '--enable-thinking', '--reasoning-budget', '8192'
    # 注意：不要加 --threads 0 / --flash-attn on —— 两者都会让速度腰斩
)
if (-not $NoWebui) {
    if (Test-Path (Join-Path $uiDir 'index.html')) { $exeArgs += @('--webui', '--ui-dir', $uiDir) }
    else { Write-Warning "未找到 Web UI（$uiDir），以纯 API 模式启动" }
} else {
    $exeArgs += '--no-ui'
}
if ($pickMmproj) { $exeArgs += @('--mmproj', $pickMmproj.FullName, '--no-mmproj-offload', '--image-max-tokens', '512') }

switch ($effectiveSpec) {
    'dflash' { $exeArgs += @('--spec-type', 'draft-dflash', '-md', $pickDraft.FullName, '--spec-draft-n-max', "$DraftTokens") }
    'mtp'    { $exeArgs += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', '2', '--spec-kv-dtype', 'f16', '--kvmem-mtp-state', 'replay') }
    'none'   { }
}

# ---------------------------------------------------------------- 汇总 ----
Write-Host ''
Write-Host '   将使用:' -ForegroundColor White
Write-Host ("      主模型   : {0}" -f $pickMain.Name) -ForegroundColor Cyan
if ($effectiveSpec -eq 'dflash') { Write-Host ("      草稿模型 : {0}" -f $pickDraft.Name) -ForegroundColor Cyan }
if ($pickMmproj) { Write-Host ("      视觉投影 : {0}" -f $pickMmproj.Name) -ForegroundColor Cyan }
$specText = switch ($effectiveSpec) { 'dflash' { 'DFlash2（推荐，实测 +24%）' } 'mtp' { 'MTP' } default { '关闭' } }
Write-Host ("      加速方式 : {0}" -f $specText) -ForegroundColor Cyan
Write-Host ("      上下文   : {0}   检索窗口: {1}   单轮上限: {2}" -f $Context, $Budget, $Reserve) -ForegroundColor Gray
foreach ($n in $notice) { Write-Host ("      [!] {0}" -f $n) -ForegroundColor Yellow }
if ($effectiveSpec -ne 'dflash' -and -not $hasDraft) {
    Write-Host '      [i] 把 DFlash2 草稿模型放进 models\ 可再提速约 24%：' -ForegroundColor Green
    Write-Host '          https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF' -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host ''
    Write-Host '   完整命令:' -ForegroundColor White
    Write-Host ("     `"{0}`" {1}" -f $exe, (($exeArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' ')) -ForegroundColor DarkGray
    Write-Host ''
    return
}

Write-Host ''
Write-Host ("   界面: http://{0}:{1}/   （Ctrl+C 停止）" -f $HostAddress, $Port) -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ''

$oldPath = $env:PATH
try {
    $env:PATH = (Join-Path $root 'bin') + ';' + $env:PATH
    & $exe @exeArgs
    $code = $LASTEXITCODE
} finally {
    $env:PATH = $oldPath
}
exit $code
