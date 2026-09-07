# ============================================================
# TunnelKeeper Gateway v3
# Dynamic Tunnel & DNS Service
# ============================================================
#
# What this does:
#   1. Starts a free Pinggy TCP tunnel pointed at your Minecraft server
#   2. Reads the public address/port Pinggy assigns
#   3. Updates your DNS SRV record so your domain always
#      points at the current tunnel
#   4. Uses HOT-SWAP to pre-start a replacement tunnel before
#      the old one expires, achieving near-zero downtime
#
# Requires: OpenSSH client (built into Windows 10/11), PowerShell
# ============================================================

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Status
)

# ---------------------- CONFIG ----------------------
# Defaults (can be overridden in .env)
$DnsProvider        = "Hostinger"
$HostingerToken     = ""
$CloudflareApiToken = ""
$CloudflareZoneId   = ""
$RootDomain         = ""
$SrvRecordName      = "_minecraft._tcp.play"
$LocalPort          = 25565
$Priority           = 0
$Weight             = 5
$TTL                = 60
$HotSwapMinute      = 55
$LogRetentionDays   = 14

$EnvPath = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $EnvPath)) {
    $parentEnv = Join-Path (Split-Path -Parent $PSScriptRoot) ".env"
    if (Test-Path $parentEnv) {
        $EnvPath = $parentEnv
    }
}
if (Test-Path $EnvPath) {
    foreach ($line in Get-Content $EnvPath) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()
            if ($val -match '^["''](.*)["'']$') { $val = $matches[1] }
            switch ($key) {
                "DnsProvider"        { $DnsProvider        = $val }
                "HostingerToken"     { $HostingerToken     = $val }
                "CloudflareApiToken" { $CloudflareApiToken = $val }
                "CloudflareToken"    { $CloudflareApiToken = $val }
                "CloudflareZoneId"   { $CloudflareZoneId   = $val }
                "RootDomain"         { $RootDomain         = $val }
                "SrvRecordName"      { $SrvRecordName      = $val }
                "LocalPort"          { $LocalPort          = [int]$val }
                "Priority"           { $Priority           = [int]$val }
                "Weight"             { $Weight             = [int]$val }
                "TTL"                { $TTL              = [int]$val }
                "HotSwapMinute"      { $HotSwapMinute    = [int]$val }
                "LogRetentionDays"   { $LogRetentionDays = [int]$val }
            }
        }
    }
}

# Auto-detect provider if not explicitly given
if ([string]::IsNullOrWhiteSpace($DnsProvider) -or $DnsProvider -eq "Hostinger") {
    if ([string]::IsNullOrEmpty($HostingerToken) -and -not [string]::IsNullOrEmpty($CloudflareApiToken)) {
        $DnsProvider = "Cloudflare"
    } else {
        $DnsProvider = "Hostinger"
    }
}

# Base logging directory setup
$script:LogDir = Join-Path $env:USERPROFILE "TunnelKeeper_Logs"
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

function Get-LogFilePath {
    return Join-Path $script:LogDir ("gateway_$(Get-Date -Format 'yyyy-MM-dd').log")
}
$script:LogFile     = Get-LogFilePath
$script:CycleCount  = 0
$script:SwapCount   = 0
$script:ScriptStart = Get-Date

function Get-PlayerAddress {
    param([string]$Srv, [string]$Domain)
    if ([string]::IsNullOrWhiteSpace($Domain)) { return "<Domain Not Configured>" }
    if ($Srv -match '^_[^.]+\._[^.]+\.(.+)$') {
        $sub = $matches[1].TrimEnd('.')
        if (-not [string]::IsNullOrWhiteSpace($sub)) {
            return "$sub.$Domain"
        }
    }
    return $Domain
}

function Test-LocalServer {
    param([int]$Port = $LocalPort)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(1000, $false)
        if ($wait -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
        $client.Dispose()
    }
}

function Show-ServiceStatus {
    $schedTask = Get-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    $taskRunning = ($schedTask -and $schedTask.State -eq "Running")

    $mutexLocked = $false
    try {
        $testMutex = [System.Threading.Mutex]::OpenExisting("Global\TunnelKeeper_Gateway")
        $mutexLocked = ($null -ne $testMutex)
        if ($testMutex) { $testMutex.Dispose() }
    } catch {
        $mutexLocked = $false
    }

    $sshProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io" -or $_.CommandLine -match "$LocalPort")
    }

    $localServerUp = Test-LocalServer -Port $LocalPort

    $liveDns = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($RootDomain)) {
            $recs = Resolve-DnsName -Name "$SrvRecordName.$RootDomain" -Type SRV -ErrorAction SilentlyContinue
            if ($recs) {
                $liveDns = "$(($recs[0].Target).TrimEnd('.')):$($recs[0].Port)"
            }
        }
    } catch {}

    $logPath = Get-LogFilePath
    $lastLog = ""
    if (Test-Path $logPath) {
        $tail = Get-Content -Path $logPath -Tail 4 -ErrorAction SilentlyContinue
        if ($tail) { $lastLog = ($tail -join "`n  |  ") }
    }

    $playerAddr = Get-PlayerAddress -Srv $SrvRecordName -Domain $RootDomain

    Write-Host ""
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host "   TunnelKeeper Gateway - Status Check                   " -ForegroundColor White
    Write-Host "  =======================================================" -ForegroundColor Cyan

    Write-Host "  |  Service State : " -NoNewline
    if ($taskRunning) {
        Write-Host "ACTIVE (Task Scheduler: Running)" -ForegroundColor Green
    } elseif ($mutexLocked -or $sshProcs) {
        Write-Host "ACTIVE (Interactive Process)" -ForegroundColor Green
    } else {
        Write-Host "STOPPED" -ForegroundColor Red
    }

    Write-Host "  |  Minecraft Svr : " -NoNewline
    if ($localServerUp) {
        Write-Host "ONLINE (Port $LocalPort responding)" -ForegroundColor Green
    } else {
        Write-Host "NOT DETECTED (Port $LocalPort closed/idle)" -ForegroundColor Yellow
    }

    Write-Host "  |  DNS Provider  : $DnsProvider" -ForegroundColor White
    Write-Host "  |  Domain Target : $playerAddr" -ForegroundColor White
    Write-Host "  |  Live SRV DNS  : " -NoNewline
    if ($liveDns) {
        Write-Host "$liveDns" -ForegroundColor Green
    } else {
        Write-Host "Unresolved / None" -ForegroundColor Yellow
    }

    $sshCount = @($sshProcs).Count
    Write-Host "  |  SSH Processes : $sshCount active" -ForegroundColor DarkGray
    Write-Host "  |  Log File      : $logPath" -ForegroundColor DarkGray
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray

    if ($lastLog) {
        Write-Host "  Recent Log Activity:" -ForegroundColor Yellow
        Write-Host "  |  $lastLog" -ForegroundColor Gray
        Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    }

    Write-Host "  Commands:" -ForegroundColor Cyan
    Write-Host "    View live log : Get-Content -Path '$logPath' -Wait -Tail 20" -ForegroundColor DarkGray
    Write-Host "    Take over     : .\minecraft-tunnel-autostart.ps1 -Force" -ForegroundColor DarkGray
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host ""
}

# If user requested status report, show it and exit
if ($Status) {
    Show-ServiceStatus
    exit 0
}

# Validate DNS Provider Token
if ($DnsProvider -match "cloudflare") {
    if ([string]::IsNullOrWhiteSpace($CloudflareApiToken)) {
        Write-Host ""
        Write-Host "  [CONFIG ERROR] CloudflareApiToken not found!" -ForegroundColor Red
        Write-Host "  Please set CloudflareApiToken in .env (or configure it in TunnelKeeper GUI)." -ForegroundColor Yellow
        Write-Host "  Refer to .env.example for guidance." -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }
} else {
    if ([string]::IsNullOrWhiteSpace($HostingerToken)) {
        Write-Host ""
        Write-Host "  [CONFIG ERROR] HostingerToken not found!" -ForegroundColor Red
        Write-Host "  Please set HostingerToken in .env (or configure it in TunnelKeeper GUI)." -ForegroundColor Yellow
        Write-Host "  Refer to .env.example for guidance." -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }
}

# Validate RootDomain (Required: must not be empty or placeholder)
if ([string]::IsNullOrWhiteSpace($RootDomain) -or $RootDomain -in @("yourdomain.com", "example.com")) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] RootDomain is not configured!" -ForegroundColor Red
    Write-Host "  You must configure your own registered domain name (e.g. yourdomain.com)." -ForegroundColor Yellow
    Write-Host "  Set 'RootDomain=yourdomain.com' in .env or via TunnelKeeper GUI -> Settings." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Validate SrvRecordName
if ([string]::IsNullOrWhiteSpace($SrvRecordName)) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] SrvRecordName cannot be empty!" -ForegroundColor Red
    Write-Host "  Set SrvRecordName in .env (e.g. _minecraft._tcp.play)." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Validate LocalPort
if ($LocalPort -lt 1 -or $LocalPort -gt 65535) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] LocalPort ($LocalPort) is invalid. Must be between 1 and 65535." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Validate Priority & Weight
if ($Priority -lt 0 -or $Priority -gt 65535) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] Priority ($Priority) must be between 0 and 65535." -ForegroundColor Red
    Write-Host ""
    exit 1
}
if ($Weight -lt 0 -or $Weight -gt 65535) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] Weight ($Weight) must be between 0 and 65535." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Validate TTL
if ($TTL -lt 1) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] TTL ($TTL) must be at least 1 second." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Validate HotSwapMinute
if ($HotSwapMinute -lt 5 -or $HotSwapMinute -gt 59) {
    Write-Host ""
    Write-Host "  [CONFIG ERROR] HotSwapMinute ($HotSwapMinute) must be between 5 and 59 minutes." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ============================================================
# LOGGING & STATE
# ============================================================

# Disable QuickEdit Mode to prevent accidental freezing when clicking the console
if (-not ("ConsoleHelper" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    const uint ENABLE_QUICK_EDIT = 0x0040;
    const int STD_INPUT_HANDLE = -10;
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static void DisableQuickEdit() {
        IntPtr consoleHandle = GetStdHandle(STD_INPUT_HANDLE);
        uint consoleMode;
        if (GetConsoleMode(consoleHandle, out consoleMode)) {
            consoleMode &= ~ENABLE_QUICK_EDIT;
            SetConsoleMode(consoleHandle, consoleMode);
        }
    }
}
"@
}
[ConsoleHelper]::DisableQuickEdit()

function Invoke-LogCleanup {
    param([int]$DaysToKeep = 14)
    if ($DaysToKeep -le 0) { return }
    try {
        if (Test-Path $script:LogDir) {
            $cutoff = (Get-Date).AddDays(-$DaysToKeep)
            $oldFiles = Get-ChildItem -Path $script:LogDir -Filter "gateway_*.log" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff }
            $count = 0
            foreach ($f in $oldFiles) {
                Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
                $count++
            }
            if ($count -gt 0) {
                Write-Log "[Logs] Cleaned up $count log file(s) older than $DaysToKeep days." "DarkGray"
            }
        }
    } catch {}
}

# ============================================================
# DISPLAY & LOGGING HELPERS
# ============================================================

function Sanitize-LogMessage {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if (-not [string]::IsNullOrEmpty($HostingerToken) -and $HostingerToken.Length -ge 8) {
        $Text = $Text -replace [regex]::Escape($HostingerToken), "****************"
    }
    if (-not [string]::IsNullOrEmpty($CloudflareApiToken) -and $CloudflareApiToken.Length -ge 8) {
        $Text = $Text -replace [regex]::Escape($CloudflareApiToken), "****************"
    }
    return $Text
}

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $Message = Sanitize-LogMessage $Message
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path (Get-LogFilePath) -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Write-Display {
    param([string]$Message, [string]$Color = "Gray")
    $Message = Sanitize-LogMessage $Message
    Write-Host $Message -ForegroundColor $Color
    try { Add-Content -Path (Get-LogFilePath) -Value $Message -ErrorAction SilentlyContinue } catch {}
}

function Get-UptimeString {
    $up = (Get-Date) - $script:ScriptStart
    $d = [math]::Floor($up.TotalDays)
    $h = $up.Hours
    $m = $up.Minutes
    if ($d -gt 0) { return "${d}d ${h}h ${m}m" }
    return "${h}h ${m}m"
}

function Show-Banner {
    Write-Display ""
    Write-Display "  =======================================================" "Cyan"
    Write-Display "                                                         " "Cyan"
    Write-Display "    _______                     _ _  __                  " "Cyan"
    Write-Display "   |__   __|                   | | |/ /                  " "Cyan"
    Write-Display "      | |_   _ _ __  _ __   ___| | ' / ___  ___ _ __     " "Cyan"
    Write-Display "      | | | | | '_ \| '_ \ / _ \ |  < / _ \/ _ \ '_ \    " "Cyan"
    Write-Display "      | | |_| | | | | | | |  __/ | . \  __/  __/ |_) |   " "Cyan"
    Write-Display "      |_|\__,_|_| |_|_| |_|\___|_|_|\_\___|\___| .__/    " "Cyan"
    Write-Display "                                                | |      " "Cyan"
    Write-Display "                                                |_|      " "Cyan"
    Write-Display "                   TunnelKeeper Gateway                  " "White"
    Write-Display "               Dynamic Tunnel & DNS Service              " "DarkCyan"
    Write-Display "                                                         " "Cyan"
    Write-Display "  =======================================================" "Cyan"
    Write-Display ""
}

function Show-Config {
    $playerAddr = Get-PlayerAddress -Srv $SrvRecordName -Domain $RootDomain
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display "  |  Configuration" "White"
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display "  |  DNS Provider: $DnsProvider" "DarkCyan"
    Write-Display "  |  Domain      : $playerAddr" "DarkCyan"
    Write-Display "  |  SRV Record  : $SrvRecordName.$RootDomain" "DarkCyan"
    Write-Display "  |  Local Port  : $LocalPort" "DarkCyan"
    Write-Display "  |  Hot-Swap    : ${HotSwapMinute} min" "DarkCyan"
    Write-Display "  |  DNS TTL     : ${TTL}s" "DarkCyan"
    Write-Display "  |  SRV Pri/Wgt : Pri: ${Priority}, Wgt: ${Weight}" "DarkCyan"
    Write-Display "  |  Log File    : $(Get-LogFilePath)" "DarkCyan"
    Write-Display "  |  Retention   : ${LogRetentionDays} days" "DarkCyan"
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display ""
}

function Show-Status {
    param([string]$TunnelAddr, [int]$TunnelPort)
    $up = Get-UptimeString
    $playerAddr = Get-PlayerAddress -Srv $SrvRecordName -Domain $RootDomain
    Write-Display ""
    Write-Display "  -------------------------------------------------------" "Green"
    Write-Display "  |  TUNNEL ACTIVE" "Green"
    Write-Display "  -------------------------------------------------------" "Green"
    Write-Display "  |  Address  : ${TunnelAddr}:${TunnelPort}" "White"
    Write-Display "  |  Domain   : $playerAddr" "White"
    Write-Display "  |  Swap In  : ~$HotSwapMinute min" "White"
    Write-Display "  |  Cycle    : #$($script:CycleCount) (Swaps: $($script:SwapCount))  |  Uptime: $up" "White"
    Write-Display "  -------------------------------------------------------" "Green"
    Write-Display ""
}

function Show-Separator {
    Write-Display ""
    Write-Display "  =======================================================" "DarkGray"
    Write-Display ""
}

# ============================================================
# DNS FUNCTIONS
# ============================================================

function Remove-OldSrvRecords {
    $headers = @{
        "Authorization" = "Bearer $HostingerToken"
        "Content-Type"  = "application/json"
    }
    $body = @{
        filters = @(
            @{
                name = $SrvRecordName
                type = "SRV"
            }
        )
    } | ConvertTo-Json -Depth 5

    try {
        $uri = "https://developers.hostinger.com/api/dns/v1/zones/$RootDomain"
        Invoke-RestMethod -Uri $uri -Method DELETE -Headers $headers -Body $body | Out-Null
        Write-Log "[DNS] Cleaned up old SRV records" "DarkGray"
        return $true
    } catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($status -eq 404) {
            Write-Log "[DNS] No old SRV records to clean (404)" "DarkGray"
            return $true
        } else {
            Write-Log "[DNS] Warning: could not clean old records: $_" "Yellow"
            return $false
        }
    }
}

function Update-HostingerSRV {
    param(
        [string]$TargetHost,
        [int]$TargetPort
    )

    $deleteOk = Remove-OldSrvRecords
    if (-not $deleteOk) {
        Write-Log "[DNS] Delete failed - skipping PUT to avoid duplicate. Will retry." "Yellow"
        return $false
    }

    Start-Sleep -Seconds 2

    $body = @{
        overwrite = $false
        zone = @(
            @{
                name    = $SrvRecordName
                type    = "SRV"
                ttl     = $TTL
                records = @(
                    @{ content = "$Priority $Weight $TargetPort $TargetHost." }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    $headers = @{
        "Authorization" = "Bearer $HostingerToken"
        "Content-Type"  = "application/json"
    }

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $uri = "https://developers.hostinger.com/api/dns/v1/zones/$RootDomain"
            Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body | Out-Null
            Write-Log "[DNS] Updated $SrvRecordName.$RootDomain -> ${TargetHost}:${TargetPort}" "Green"
            return $true
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Log "[DNS] PUT attempt $attempt/$maxRetries returned an error. Retrying in 5 seconds..." "Yellow"
                Start-Sleep -Seconds 5
            } else {
                Write-Log "[DNS] All $maxRetries attempts failed: $_" "Red"
            }
        }
    }
    return $false
}

$script:CachedCloudflareZoneId = $null

function Get-CloudflareZoneId {
    if (-not [string]::IsNullOrEmpty($CloudflareZoneId)) {
        return $CloudflareZoneId
    }
    if (-not [string]::IsNullOrEmpty($script:CachedCloudflareZoneId)) {
        return $script:CachedCloudflareZoneId
    }
    $headers = @{
        "Authorization" = "Bearer $CloudflareApiToken"
        "Content-Type"  = "application/json"
    }
    try {
        $uri = "https://api.cloudflare.com/client/v4/zones?name=$RootDomain"
        $resp = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
        if ($resp.success -and $resp.result -and $resp.result.Count -gt 0) {
            $script:CachedCloudflareZoneId = $resp.result[0].id
            return $script:CachedCloudflareZoneId
        } else {
            Write-Log "[Cloudflare] Zone '$RootDomain' not found in Cloudflare account." "Red"
        }
    } catch {
        Write-Log "[Cloudflare] Error retrieving Zone ID for '$RootDomain': $_" "Red"
    }
    return $null
}

function Update-CloudflareSRV {
    param(
        [string]$TargetHost,
        [int]$TargetPort
    )

    $zoneId = Get-CloudflareZoneId
    if (-not $zoneId) {
        Write-Log "[Cloudflare] Cannot update DNS without a valid Zone ID." "Red"
        return $false
    }

    $headers = @{
        "Authorization" = "Bearer $CloudflareApiToken"
        "Content-Type"  = "application/json"
    }

    # Parse service, proto, and name from $SrvRecordName (e.g. _minecraft._tcp.play or _minecraft._tcp)
    $service = "_minecraft"
    $proto   = "_tcp"
    $name    = "@"

    if ($SrvRecordName -match '^_([a-zA-Z0-9]+)\._([a-zA-Z0-9]+)\.?(.*)$') {
        $service = "_$($matches[1])"
        $proto   = "_$($matches[2])"
        $name    = if ($matches[3]) { $matches[3] } else { "@" }
    }

    $fullRecordName = "$SrvRecordName.$RootDomain"

    # Cloudflare SRV data payload
    $bodyObj = @{
        type = "SRV"
        name = $fullRecordName
        ttl  = $TTL
        data = @{
            service  = $service
            proto    = $proto
            name     = $name
            priority = $Priority
            weight   = $Weight
            port     = $TargetPort
            target   = $TargetHost.TrimEnd('.')
        }
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5

    # Check if record already exists
    $existingRecordId = $null
    try {
        $searchUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=SRV&name=$fullRecordName"
        $searchResp = Invoke-RestMethod -Uri $searchUri -Method GET -Headers $headers
        if ($searchResp.success -and $searchResp.result -and $searchResp.result.Count -gt 0) {
            $existingRecordId = $searchResp.result[0].id
        }
    } catch {
        Write-Log "[Cloudflare] Querying existing SRV record returned error: $_" "Yellow"
    }

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            if ($existingRecordId) {
                # Update existing record
                $putUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$existingRecordId"
                $resp = Invoke-RestMethod -Uri $putUri -Method PUT -Headers $headers -Body $bodyJson
            } else {
                # Create new record
                $postUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
                $resp = Invoke-RestMethod -Uri $postUri -Method POST -Headers $headers -Body $bodyJson
                if ($resp.success -and $resp.result) {
                    $existingRecordId = $resp.result.id
                }
            }

            if ($resp.success) {
                Write-Log "[DNS] Updated $SrvRecordName.$RootDomain -> ${TargetHost}:${TargetPort} (Cloudflare)" "Green"
                return $true
            } else {
                Write-Log "[Cloudflare] API error: $($resp.errors | ConvertTo-Json -Compress)" "Yellow"
            }
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Log "[DNS] Cloudflare update attempt $attempt/$maxRetries returned an error. Retrying in 5 seconds..." "Yellow"
                Start-Sleep -Seconds 5
            } else {
                Write-Log "[DNS] All $maxRetries Cloudflare attempts failed: $_" "Red"
            }
        }
    }
    return $false
}

function Update-DnsSRV {
    param(
        [string]$TargetHost,
        [int]$TargetPort
    )
    if ($DnsProvider -match "cloudflare") {
        return Update-CloudflareSRV -TargetHost $TargetHost -TargetPort $TargetPort
    } else {
        return Update-HostingerSRV -TargetHost $TargetHost -TargetPort $TargetPort
    }
}

function Test-DnsPropagation {
    param(
        [string]$ExpectedHost,
        [int]$ExpectedPort
    )
    $fullSrv = "$SrvRecordName.$RootDomain"
    try {
        $records = Resolve-DnsName -Name $fullSrv -Type SRV -ErrorAction SilentlyContinue
        if ($records) {
            foreach ($r in $records) {
                $target = ("" + $r.Target).TrimEnd('.')
                $port = $r.Port
                if ($target -eq $ExpectedHost.TrimEnd('.') -and $port -eq $ExpectedPort) {
                    Write-Log "[DNS] Verified live SRV propagation: $fullSrv -> ${target}:${port}" "Green"
                    return $true
                }
            }
            Write-Log "[DNS] $DnsProvider updated. Propagating to resolvers... (current: $(($records[0].Target).TrimEnd('.')):$($records[0].Port))" "DarkGray"
        }
    } catch {}
    return $false
}

# ============================================================
# TUNNEL FUNCTIONS
# ============================================================

function Start-Tunnel {
    param([string]$Label = "Tunnel")

    $tunnel = @{
        proc       = $null
        state      = $null
        outHandler = $null
        errHandler = $null
        startTime  = Get-Date
        success    = $false
    }

    $tunnel.state = [hashtable]::Synchronized(@{
        output     = [System.Text.StringBuilder]::new()
        lockObj    = [object]::new()
        tunnelHost = ""
        tunnelPort = 0
        urlFound   = $false
    })

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "ssh"
    $psi.Arguments              = "-T -o StrictHostKeyChecking=no -p 443 -R0:localhost:$LocalPort tcp@a.pinggy.io"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.EnvironmentVariables["SSH_ASKPASS"]        = "`"$env:SSH_ASKPASS`""
    $psi.EnvironmentVariables["SSH_ASKPASS_REQUIRE"] = "force"
    $psi.EnvironmentVariables["DISPLAY"]             = ":0"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $tunnel.proc = $proc

    $tunnel.outHandler = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -MessageData $tunnel.state -Action {
        if ($EventArgs.Data) {
            $s = $Event.MessageData
            if ($EventArgs.Data -match "^\s*(RB|TB|Connections|Bytes|Tunnels):") { return }
            [System.Threading.Monitor]::Enter($s.lockObj)
            try {
                $s.output.AppendLine($EventArgs.Data)
            } finally {
                [System.Threading.Monitor]::Exit($s.lockObj)
            }
            if (-not $s.urlFound) {
                $m = [regex]::Match($EventArgs.Data, "tcp://(.*?):(\d+)")
                if ($m.Success) {
                    $s.tunnelHost = $m.Groups[1].Value
                    $s.tunnelPort = [int]$m.Groups[2].Value
                    $s.urlFound   = $true
                }
            }
        }
    }

    $tunnel.errHandler = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -MessageData $tunnel.state -Action {
        if ($EventArgs.Data) {
            $s = $Event.MessageData
            if ($EventArgs.Data -match "^\s*(RB|TB|Connections|Bytes|Tunnels):") { return }
            [System.Threading.Monitor]::Enter($s.lockObj)
            try {
                $s.output.AppendLine($EventArgs.Data)
            } finally {
                [System.Threading.Monitor]::Exit($s.lockObj)
            }
            if (-not $s.urlFound) {
                $m = [regex]::Match($EventArgs.Data, "tcp://(.*?):(\d+)")
                if ($m.Success) {
                    $s.tunnelHost = $m.Groups[1].Value
                    $s.tunnelPort = [int]$m.Groups[2].Value
                    $s.urlFound   = $true
                }
            }
        }
    }

    try {
        $proc.Start() | Out-Null
    } catch {
        Write-Log "[$Label] Could not start SSH: $_" "Red"
        return $tunnel
    }

    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $tunnel.startTime = Get-Date

    # Send blank password lines (exit early if tunnel URL is discovered)
    for ($i = 1; $i -le 5; $i++) {
        if ($tunnel.state.urlFound) { break }
        Start-Sleep -Milliseconds 1000
        if ($tunnel.state.urlFound) { break }
        try {
            if (-not $proc.HasExited) {
                $proc.StandardInput.WriteLine("")
                $proc.StandardInput.Flush()
            } else { break }
        } catch { break }
        if ($tunnel.state.urlFound) { break }
        Start-Sleep -Milliseconds 1000
        if ($tunnel.state.urlFound) { break }
    }

    # Wait for the tunnel URL (timeout: 60 seconds)
    $urlWaitStart = Get-Date
    while ((-not $tunnel.state.urlFound) -and (-not $proc.HasExited)) {
        Start-Sleep -Milliseconds 500
        if (((Get-Date) - $urlWaitStart).TotalSeconds -gt 60) {
            Write-Log "[$Label] No URL detected after 60 seconds." "Red"
            try { $proc.Kill() } catch {}
            return $tunnel
        }
    }

    if ($tunnel.state.urlFound) {
        $tunnel.success = $true
    }

    return $tunnel
}

function Stop-Tunnel {
    param($tunnel)
    if ($null -eq $tunnel) { return }

    if ($tunnel.outHandler) {
        Unregister-Event -SourceIdentifier $tunnel.outHandler.Name -ErrorAction SilentlyContinue
        Remove-Job -Name $tunnel.outHandler.Name -Force -ErrorAction SilentlyContinue
    }
    if ($tunnel.errHandler) {
        Unregister-Event -SourceIdentifier $tunnel.errHandler.Name -ErrorAction SilentlyContinue
        Remove-Job -Name $tunnel.errHandler.Name -Force -ErrorAction SilentlyContinue
    }
    if ($tunnel.proc) {
        try { if (-not $tunnel.proc.HasExited) { $tunnel.proc.Kill() } } catch {}
        try { $tunnel.proc.StandardInput.Close() } catch {}
        try { $tunnel.proc.Close() } catch {}
        try { $tunnel.proc.Dispose() } catch {}
    }
}

# ============================================================
# MAIN
# ============================================================

# Duplicate instance guard
$mutex = $null
$hasMutex = $false

if ($Force) {
    Write-Host ""
    Write-Host "[Gateway] -Force specified. Stopping background task and existing tunnels..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io" -or $_.CommandLine -match "$LocalPort")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

try {
    $mutex = New-Object System.Threading.Mutex($false, "Global\TunnelKeeper_Gateway")
    $hasMutex = $mutex.WaitOne(0)
} catch [System.UnauthorizedAccessException] {
    # Mutex is held by the background Task Scheduler process
    $hasMutex = $false
} catch [System.Threading.AbandonedMutexException] {
    # Previous instance exited abruptly; we now safely own the mutex
    $hasMutex = $true
} catch {
    $hasMutex = $false
}

if (-not $hasMutex) {
    $schedTask = Get-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    $logPath = Get-LogFilePath
    Write-Host ""
    if ($schedTask -and $schedTask.State -eq "Running") {
        Write-Host "  =======================================================" -ForegroundColor Cyan
        Write-Host "   NOTE: Minecraft Tunnel is ALREADY RUNNING!            " -ForegroundColor Green
        Write-Host "  =======================================================" -ForegroundColor Cyan
        Write-Host "   The tunnel is active in the background via Windows    " -ForegroundColor White
        Write-Host "   Task Scheduler ('Minecraft Tunnel Keeper').           " -ForegroundColor White
        Write-Host "                                                         " -ForegroundColor White
        Write-Host "   Your domain (play.$RootDomain) is already live!       " -ForegroundColor Green
        Write-Host "   Log file: $logPath                                    " -ForegroundColor DarkGray
        Write-Host "                                                         " -ForegroundColor White
        Write-Host "   To check status:                                      " -ForegroundColor Yellow
        Write-Host "     & `"$PSCommandPath`" -Status                         " -ForegroundColor White
        Write-Host "                                                         " -ForegroundColor White
        Write-Host "   To view live logs:                                    " -ForegroundColor Yellow
        Write-Host "     Get-Content -Path '$logPath' -Wait -Tail 20         " -ForegroundColor White
        Write-Host "                                                         " -ForegroundColor White
        Write-Host "   To take over and run interactively in this window:    " -ForegroundColor Yellow
        Write-Host "     & `"$PSCommandPath`" -Force                         " -ForegroundColor White
        Write-Host "  =======================================================" -ForegroundColor Cyan
    } else {
        Write-Host "  =======================================================" -ForegroundColor Red
        Write-Host "     ERROR: Another instance is already running!         " -ForegroundColor Red
        Write-Host "     To check status : & `"$PSCommandPath`" -Status      " -ForegroundColor Yellow
        Write-Host "     To force restart: & `"$PSCommandPath`" -Force       " -ForegroundColor Yellow
        Write-Host "  =======================================================" -ForegroundColor Red
    }
    Write-Host ""
    exit 0
}

# Auto-cleanup orphan SSH processes if PowerShell exits abruptly
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io" -or $_.CommandLine -match "$LocalPort")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} -SupportEvent | Out-Null

try {
    # SSH_ASKPASS setup
    $askPassScript = Join-Path $env:TEMP "pinggy_askpass.cmd"
    Set-Content -Path $askPassScript -Value "echo." -Encoding ASCII
    $env:SSH_ASKPASS         = "`"$askPassScript`""
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY             = ":0"

    # Startup maintenance
    Invoke-LogCleanup -DaysToKeep $LogRetentionDays

    # Startup display
    Show-Banner
    Show-Config

    Write-Log "Gateway started. Logs saved to: $(Get-LogFilePath)" "DarkGray"

    # Pre-flight check for Minecraft server
    if (-not (Test-LocalServer -Port $LocalPort)) {
        Write-Log "[Pre-flight] Notice: Local Minecraft server not detected on port $LocalPort yet. Proceeding with tunnel..." "Yellow"
    } else {
        Write-Log "[Pre-flight] Local Minecraft server is online on port $LocalPort." "Green"
    }

    # ---- Main Loop ----
    while ($true) {
        $script:CycleCount++
        Show-Separator
        Write-Log "[Cycle #$($script:CycleCount)] Starting Pinggy tunnel for localhost:$LocalPort ..." "Cyan"

        $tunnel = Start-Tunnel -Label "Tunnel"

        if (-not $tunnel.success) {
            Write-Log "[Tunnel] Failed to establish tunnel. Retrying in 10 seconds..." "Red"
            Stop-Tunnel $tunnel
            Start-Sleep -Seconds 10
            continue
        }

        # Print initial SSH output
        $currentOutput = $tunnel.state.output.ToString()
        if ($currentOutput.Length -gt 0) {
            Write-Host $currentOutput -NoNewline
            try { Add-Content -Path (Get-LogFilePath) -Value $currentOutput -ErrorAction SilentlyContinue } catch {}
        }
        $lastOutputLen = $currentOutput.Length

        Write-Log "[Tunnel] Detected: $($tunnel.state.tunnelHost):$($tunnel.state.tunnelPort)" "Cyan"
        $dnsUpdated = Update-DnsSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort

        if ($dnsUpdated) {
            Test-DnsPropagation -ExpectedHost $tunnel.state.tunnelHost -ExpectedPort $tunnel.state.tunnelPort | Out-Null
            Show-Status -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
        }

        $hotSwapStarted     = $false
        $lastHotSwapAttempt = $null
        $lastDnsRetry       = Get-Date
        $pendingOldTunnel   = $null
        $swapTime           = $null

        # ---- Monitoring Loop ----
        while (-not $tunnel.proc.HasExited) {
            Start-Sleep -Milliseconds 1000

            # Print any new output
            $currentOutput = ""
            [System.Threading.Monitor]::Enter($tunnel.state.lockObj)
            try {
                $currentOutput = $tunnel.state.output.ToString()
            } finally {
                [System.Threading.Monitor]::Exit($tunnel.state.lockObj)
            }
            if ($currentOutput.Length -gt $lastOutputLen) {
                $newText = $currentOutput.Substring($lastOutputLen)
                Write-Host $newText -NoNewline
                try { Add-Content -Path (Get-LogFilePath) -Value $newText -ErrorAction SilentlyContinue } catch {}
                $lastOutputLen = $currentOutput.Length
            }

            # DNS retry every 30 seconds if last update failed
            if ((-not $dnsUpdated) -and $tunnel.state.urlFound) {
                $sinceLast = ((Get-Date) - $lastDnsRetry).TotalSeconds
                if ($sinceLast -ge 30) {
                    Write-Log "[DNS] Retrying DNS update..." "Yellow"
                    $dnsUpdated = Update-DnsSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort
                    $lastDnsRetry = Get-Date
                    if ($dnsUpdated) {
                        Test-DnsPropagation -ExpectedHost $tunnel.state.tunnelHost -ExpectedPort $tunnel.state.tunnelPort | Out-Null
                        Show-Status -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
                    }
                }
            }

            # Clean up old tunnel when it dies naturally (or safety timeout at 10 min)
            if ($null -ne $pendingOldTunnel) {
                $oldExited     = $pendingOldTunnel.proc.HasExited
                $safetyTimeout = (((Get-Date) - $swapTime).TotalSeconds -ge 600)
                if ($oldExited -or $safetyTimeout) {
                    if ($oldExited) {
                        Write-Log "[HotSwap] Old tunnel exited naturally. Cleaned up." "DarkGray"
                    } else {
                        Write-Log "[HotSwap] Old tunnel safety timeout (10 min). Force cleanup." "Yellow"
                    }
                    Stop-Tunnel $pendingOldTunnel
                    $pendingOldTunnel = $null
                }
            }

            # Hot-swap: pre-start replacement tunnel before expiry
            $elapsed = ((Get-Date) - $tunnel.startTime).TotalMinutes
            $canRetrySwap = ($null -eq $lastHotSwapAttempt) -or (((Get-Date) - $lastHotSwapAttempt).TotalSeconds -ge 60)
            if ($elapsed -ge $HotSwapMinute -and $elapsed -lt 68 -and -not $hotSwapStarted -and $canRetrySwap) {
                $hotSwapStarted = $true
                Write-Display ""
                Write-Display "  - - - - - - - - -  HOT-SWAP  - - - - - - - - - -" "Yellow"
                Write-Log "[HotSwap] Tunnel at $([math]::Round($elapsed,1)) min. Pre-starting replacement..." "Cyan"

                $newTunnel = Start-Tunnel -Label "HotSwap"

                if ($newTunnel.success) {
                    Write-Log "[HotSwap] New tunnel: $($newTunnel.state.tunnelHost):$($newTunnel.state.tunnelPort)" "Cyan"
                    Write-Log "[HotSwap] Updating DNS to new tunnel..." "Cyan"
                    $dnsUpdated = Update-DnsSRV -TargetHost $newTunnel.state.tunnelHost -TargetPort $newTunnel.state.tunnelPort
                    if ($dnsUpdated) {
                        Test-DnsPropagation -ExpectedHost $newTunnel.state.tunnelHost -ExpectedPort $newTunnel.state.tunnelPort | Out-Null
                    }

                    # Keep old tunnel alive until Pinggy expires it
                    $pendingOldTunnel = $tunnel
                    $swapTime = Get-Date

                    # Switch monitoring to new tunnel
                    $tunnel = $newTunnel
                    $hotSwapStarted = $false
                    $lastHotSwapAttempt = $null
                    $lastOutputLen = 0
                    $lastDnsRetry = Get-Date
                    $script:CycleCount++
                    $script:SwapCount++

                    Write-Log "[HotSwap] Swap complete! (Swap #$($script:SwapCount)) Old tunnel stays alive until Pinggy expires it." "Green"
                    if ($dnsUpdated) {
                        Show-Status -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
                    }
                } else {
                    Write-Log "[HotSwap] Failed to pre-start replacement. Will retry in 60 seconds (if before min 68)..." "Yellow"
                    Stop-Tunnel $newTunnel
                    $lastHotSwapAttempt = Get-Date
                    $hotSwapStarted = $false
                }
            }

            # Watchdog: force-kill if tunnel alive for 75+ minutes
            $elapsed = ((Get-Date) - $tunnel.startTime).TotalMinutes
            if ($elapsed -gt 75) {
                Write-Display ""
                Write-Log "[Watchdog] Tunnel alive for $([math]::Round($elapsed,1)) min. Force-killing." "Yellow"
                try { $tunnel.proc.Kill() } catch {}
                break
            }
        }

        # Print any final output
        $currentOutput = ""
        [System.Threading.Monitor]::Enter($tunnel.state.lockObj)
        try {
            $currentOutput = $tunnel.state.output.ToString()
        } finally {
            [System.Threading.Monitor]::Exit($tunnel.state.lockObj)
        }
        if ($currentOutput.Length -gt $lastOutputLen) {
            $finalText = $currentOutput.Substring($lastOutputLen)
            Write-Host $finalText -NoNewline
            try { Add-Content -Path (Get-LogFilePath) -Value $finalText -ErrorAction SilentlyContinue } catch {}
        }

        # Cleanup everything
        Stop-Tunnel $tunnel
        if ($null -ne $pendingOldTunnel) {
            Stop-Tunnel $pendingOldTunnel
            $pendingOldTunnel = $null
        }

        $up = Get-UptimeString
        Write-Display ""
        Write-Log "[Cycle #$($script:CycleCount) Complete] Uptime: $up | Restarting in 5 seconds..." "Yellow"
        Start-Sleep -Seconds 5
    }
} finally {
    try {
        if ($tunnel) { Stop-Tunnel $tunnel }
        if ($pendingOldTunnel) { Stop-Tunnel $pendingOldTunnel }
        if ($askPassScript -and (Test-Path $askPassScript)) {
            Remove-Item $askPassScript -Force -ErrorAction SilentlyContinue
        }
        $mutex.ReleaseMutex()
    } catch {}
    try { $mutex.Dispose() } catch {}
}
