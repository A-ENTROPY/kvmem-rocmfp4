# ============================================================================
#  KVMem + ROCmFP4 + DFlash2 启动器（发行包版）
#
#  用法：
#     .\start-kvmem.ps1 -Model <主模型.gguf> [-Draft <DFlash2草稿.gguf>]
#     .\start-kvmem.ps1 -Model <主模型.gguf> -Mtp              # 改用 MTP 加速
#     .\start-kvmem.ps1 -Model <主模型.gguf> -NoSpec           # 关闭推测解码
#     .\start-kvmem.ps1 -Model <...> -Draft <...> -DryRun      # 只打印命令
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Model,
    [string]$Draft     = '',
    [string]$Mmproj    = '',
    [ValidateSet('dflash','mtp','none')][string]$Spec = 'dflash',
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
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe    = Join-Path $root 'bin/llama-kvmem-server.exe'
$uiDir  = Join-Path $root 'share/kvmem/ui'

if (-not (Test-Path $exe)) { throw "找不到 bin\llama-kvmem-server.exe，请确认解压完整" }
if (-not (Test-Path $Model)) { throw "找不到主模型: $Model" }

$args = @(
    '-m', $Model
    '--device', $Device, '-ngl', '99', '--load-mode', 'none'
    '--host', $HostAddress, '--port', "$Port"
    '-c', "$Context", '-b', '512', '-n', "$MaxTokens"
    '--kvmem', '--kvmem-budget', "$Budget", '--kvmem-gen-reserve', "$Reserve"
    '--kv-dtype', $KvDtype
    '--enable-thinking', '--reasoning-budget', '8192'
    # 注意：不要加 --threads 0 / --flash-attn on —— 两者都会让速度腰斩
)
if (-not $NoWebui) {
    if (Test-Path (Join-Path $uiDir 'index.html')) {
        $args += @('--webui', '--ui-dir', $uiDir)
    } else {
        Write-Warning "未找到 Web UI（$uiDir），以纯 API 模式启动"
    }
} else {
    $args += '--no-ui'
}
if ($Mmproj -and (Test-Path $Mmproj)) {
    $args += @('--mmproj', $Mmproj, '--no-mmproj-offload', '--image-max-tokens', '512')
}

switch ($Spec) {
    'dflash' {
        if (-not $Draft -or -not (Test-Path $Draft)) {
            throw "DFlash2 需要 -Draft <草稿模型.gguf>（或改用 -Spec mtp / -Spec none）"
        }
        $args += @('--spec-type', 'draft-dflash', '-md', $Draft, '--spec-draft-n-max', "$DraftTokens")
    }
    'mtp' {
        $args += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', '2', '--spec-kv-dtype', 'f16', '--kvmem-mtp-state', 'replay')
    }
    'none' { }
}

if ($DryRun) {
    Write-Host "工作目录: $root"
    Write-Host '完整命令:'
    Write-Host ("  `"$exe`" " + (($args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '))
    return
}

# 打包版自带 ROCm 运行库，优先使用；否则回退到已安装的 ROCm
$oldPath = $env:PATH
try {
    $env:PATH = (Join-Path $root 'bin') + ';' + $env:PATH
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '   KVMem + ROCmFP4 + DFlash2' -ForegroundColor Cyan
    Write-Host "   主模型   : $(Split-Path $Model -Leaf)" -ForegroundColor Gray
    if ($Spec -eq 'dflash') { Write-Host "   草稿模型 : $(Split-Path $Draft -Leaf)" -ForegroundColor Gray }
    Write-Host "   加速方式 : $Spec   |   上下文: $Context   |   端口: $Port" -ForegroundColor Gray
    Write-Host "   界面     : http://${HostAddress}:$Port/" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host ''
    & $exe @args
    $code = $LASTEXITCODE
} finally {
    $env:PATH = $oldPath
}
exit $code
