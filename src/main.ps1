<#
====================================================================
 TunnelKeeper - Unified Application Entry Point
 Mode Dispatcher: Native WPF Dashboard or Headless Console Daemon
====================================================================
#>

[CmdletBinding(DefaultParameterSetName = "GUI")]
param(
    [Parameter(ParameterSetName = "Daemon")]
    [Alias("cli", "console")]
    [switch]$Headless,

    [Parameter(ParameterSetName = "Daemon")]
    [switch]$Daemon,

    [Parameter(ParameterSetName = "GUI")]
    [switch]$Gui,

    [Parameter(ParameterSetName = "Status")]
    [switch]$Status,

    [Parameter(ParameterSetName = "Force")]
    [switch]$Force,

    [Parameter(ParameterSetName = "Validate")]
    [switch]$Validate,

    [Parameter(ParameterSetName = "Version")]
    [switch]$Version
)

$SrcDir = $PSScriptRoot
if (-not $SrcDir) { $SrcDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SrcDir) { $SrcDir = (Get-Location).Path }

$RepoRoot = if (Test-Path (Join-Path $SrcDir "..\.env.example")) {
    (Resolve-Path (Join-Path $SrcDir "..")).Path
} elseif (Test-Path (Join-Path $SrcDir "..\.env")) {
    (Resolve-Path (Join-Path $SrcDir "..")).Path
} else {
    $SrcDir
}

if ($Version) {
    Write-Host "TunnelKeeper Gateway v2.1.0" -ForegroundColor Cyan
    Write-Host "Modern Dynamic DNS & SSH Tunnel Manager for Minecraft" -ForegroundColor Gray
    Write-Host "Repository: https://github.com/CyberSphinxxx/TunnelKeeper" -ForegroundColor DarkGray
    return
}

if ($Validate) {
    Write-Host "Validating TunnelKeeper environment..." -ForegroundColor Cyan
    $envPath = Join-Path $RepoRoot ".env"
    if (-not (Test-Path $envPath)) {
        $envPath = Join-Path $SrcDir ".env"
    }

    if (-not (Test-Path $envPath)) {
        Write-Host "[FAIL] .env configuration file not found at: $envPath" -ForegroundColor Red
        Write-Host "       Copy .env.example to .env to configure your server." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[PASS] Configuration file found: $envPath" -ForegroundColor Green

    # Parse .env settings
    $cfg = @{}
    foreach ($line in Get-Content $envPath) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^([^=]+)=(.*)$') {
            $cfg[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    $provider = if ($cfg.ContainsKey("DnsProvider")) { $cfg["DnsProvider"] } else { "Hostinger" }
    Write-Host "       DNS Provider: $provider" -ForegroundColor Gray

    $valid = $true
    if ($provider -eq "Cloudflare") {
        if ([string]::IsNullOrWhiteSpace($cfg["CloudflareApiToken"]) -or $cfg["CloudflareApiToken"] -eq "YOUR_CLOUDFLARE_API_TOKEN_HERE") {
            Write-Host "[WARN] CloudflareApiToken is not configured." -ForegroundColor Yellow
            $valid = $false
        } else {
            Write-Host "[PASS] CloudflareApiToken configured." -ForegroundColor Green
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($cfg["HostingerToken"]) -or $cfg["HostingerToken"] -eq "YOUR_HOSTINGER_API_TOKEN_HERE") {
            Write-Host "[WARN] HostingerToken is not configured." -ForegroundColor Yellow
            $valid = $false
        } else {
            Write-Host "[PASS] HostingerToken configured." -ForegroundColor Green
        }
    }

    if ([string]::IsNullOrWhiteSpace($cfg["RootDomain"]) -or $cfg["RootDomain"] -in @("yourdomain.com", "example.com")) {
        Write-Host "[WARN] RootDomain is not configured." -ForegroundColor Yellow
        $valid = $false
    } else {
        Write-Host "[PASS] RootDomain configured: $($cfg['RootDomain'])" -ForegroundColor Green
    }

    if ($valid) {
        Write-Host "`nAll required configurations are set!" -ForegroundColor Green
    } else {
        Write-Host "`nPlease update your .env file before launching the tunnel." -ForegroundColor Yellow
    }
    return
}

$coreDaemon = Join-Path $SrcDir "minecraft-tunnel-autostart.ps1"
$guiScript  = Join-Path $SrcDir "TunnelKeeper-GUI.ps1"

if ($Headless -or $Daemon -or $Status -or $Force) {
    if (-not (Test-Path $coreDaemon)) {
        Write-Error "Could not locate core daemon script at: $coreDaemon"
        exit 1
    }
    $passthrough = @()
    if ($Status) { $passthrough += "-Status" }
    if ($Force)  { $passthrough += "-Force" }
    & $coreDaemon @passthrough
} else {
    if (-not (Test-Path $guiScript)) {
        Write-Error "Could not locate GUI script at: $guiScript"
        exit 1
    }
    & $guiScript
}
