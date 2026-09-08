<#
====================================================================
 TunnelKeeper - Unified Application Entry Point
 Mode Dispatcher: Native WPF Dashboard or Headless Console Daemon
====================================================================
#>

[CmdletBinding()]
param(
    [Alias("cli", "console")]
    [switch]$Headless,

    [switch]$Daemon,

    [switch]$Gui,

    [switch]$Status,

    [switch]$Force,

    [switch]$Validate,

    [switch]$Version
)

$SrcDir = $PSScriptRoot
if (-not $SrcDir) { $SrcDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SrcDir) { $SrcDir = (Get-Location).Path }

. (Join-Path $SrcDir "core\Config.ps1")
. (Join-Path $SrcDir "core\Network.ps1")

if ($Version) {
    Write-Host "TunnelKeeper Gateway v2.1.0" -ForegroundColor Cyan
    Write-Host "Modern Dynamic DNS & SSH Tunnel Manager for Minecraft" -ForegroundColor Gray
    Write-Host "Repository: https://github.com/CyberSphinxxx/TunnelKeeper" -ForegroundColor DarkGray
    return
}

if ($Validate) {
    Write-Host "Validating TunnelKeeper environment..." -ForegroundColor Cyan
    $cfg = Get-TunnelKeeperConfig
    if (-not $cfg["_EnvPath"] -or -not (Test-Path $cfg["_EnvPath"])) {
        Write-Host "[FAIL] .env configuration file not found." -ForegroundColor Red
        Write-Host "       Copy .env.example to .env to configure your server." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[PASS] Configuration file found: $($cfg['_EnvPath'])" -ForegroundColor Green
    Write-Host "       DNS Provider: $($cfg['DnsProvider'])" -ForegroundColor Gray

    $check = Test-TunnelKeeperConfig -Config $cfg
    foreach ($err in $check.Errors) {
        Write-Host "[ERROR] $err" -ForegroundColor Red
    }

    if ($check.IsValid) {
        Write-Host "[PASS] Domain: $($cfg['RootDomain'])" -ForegroundColor Green
        Write-Host "[PASS] SRV Record: $($cfg['SrvRecordName'])" -ForegroundColor Green
        Write-Host "[PASS] Local Port: $($cfg['LocalPort'])" -ForegroundColor Green
        Write-Host "`nAll required configurations are valid!" -ForegroundColor Green
    } else {
        Write-Host "`nPlease resolve the configuration errors in .env before launching." -ForegroundColor Yellow
    }
    return
}

$coreDaemon = Join-Path $SrcDir "minecraft-tunnel-autostart.ps1"
$guiScript  = Join-Path $SrcDir "TunnelKeeper-GUI.ps1"

if ($Gui -and ($Headless -or $Daemon)) {
    Write-Error "Cannot specify both -Gui and -Headless/-Daemon."
    exit 1
}

if ($Headless -or $Daemon -or $Status -or $Force) {
    if (-not (Test-Path $coreDaemon)) {
        Write-Error "Could not locate core daemon script at: $coreDaemon"
        exit 1
    }
    $params = @{}
    if ($Status) { $params["Status"] = $true }
    if ($Force)  { $params["Force"]  = $true }
    & $coreDaemon @params
} else {
    if (-not (Test-Path $guiScript)) {
        Write-Error "Could not locate GUI script at: $guiScript"
        exit 1
    }
    & $guiScript
}
