<#
============================================================
 TunnelKeeper Gateway - Dynamic Tunnel & DNS Service
 Hot-Swap Pinggy TCP Tunnel Orchestrator
============================================================
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Status
)

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Dot-source modular components
. (Join-Path $ScriptDir "core\Config.ps1")
. (Join-Path $ScriptDir "core\Logger.ps1")
. (Join-Path $ScriptDir "core\Network.ps1")
. (Join-Path $ScriptDir "providers\Hostinger.ps1")
. (Join-Path $ScriptDir "providers\Cloudflare.ps1")

# Load configuration
$cfg = Get-TunnelKeeperConfig
$DnsProvider        = $cfg["DnsProvider"]
$HostingerToken     = $cfg["HostingerToken"]
$CloudflareApiToken = $cfg["CloudflareApiToken"]
$CloudflareZoneId   = $cfg["CloudflareZoneId"]
$RootDomain         = $cfg["RootDomain"]
$SrvRecordName      = $cfg["SrvRecordName"]
$LocalPort          = $cfg["LocalPort"]
$Priority           = $cfg["Priority"]
$Weight             = $cfg["Weight"]
$TTL                = $cfg["TTL"]
$HotSwapMinute      = $cfg["HotSwapMinute"]
$LogRetentionDays   = $cfg["LogRetentionDays"]

# Mask sensitive API tokens from all log output
if ($HostingerToken) { Register-MaskToken $HostingerToken }
if ($CloudflareApiToken) { Register-MaskToken $CloudflareApiToken }

# Status inspection flag
if ($Status) {
    Show-ServiceStatus -Config $cfg
    exit 0
}

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

$script:CycleCount  = 0
$script:SwapCount   = 0
$script:ScriptStart = Get-Date

function Get-UptimeString {
    $up = (Get-Date) - $script:ScriptStart
    $d = [math]::Floor($up.TotalDays)
    $h = $up.Hours
    $m = $up.Minutes
    if ($d -gt 0) { return "${d}d ${h}h ${m}m" }
    return "${h}h ${m}m"
}

function Show-Banner {
    Write-Host ""
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host "                                                         " -ForegroundColor Cyan
    Write-Host "    _______                     _ _  __                  " -ForegroundColor Cyan
    Write-Host "   |__   __|                   | | |/ /                  " -ForegroundColor Cyan
    Write-Host "      | |_   _ _ __  _ __   ___| | ' / ___  ___ _ __     " -ForegroundColor Cyan
    Write-Host "      | | | | | '_ \| '_ \ / _ \ |  < / _ \/ _ \ '_ \    " -ForegroundColor Cyan
    Write-Host "      | | |_| | | | | | | |  __/ | . \  __/  __/ |_) |   " -ForegroundColor Cyan
    Write-Host "      |_|\__,_|_| |_|_| |_|\___|_|_|\_\___|\___| .__/    " -ForegroundColor Cyan
    Write-Host "                                                | |      " -ForegroundColor Cyan
    Write-Host "                                                |_|      " -ForegroundColor Cyan
    Write-Host "                   TunnelKeeper Gateway                  " -ForegroundColor White
    Write-Host "               Dynamic Tunnel & DNS Service              " -ForegroundColor DarkCyan
    Write-Host "                                                         " -ForegroundColor Cyan
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-ConfigDisplay {
    $playerAddr = Get-PlayerAddress -Srv $SrvRecordName -Domain $RootDomain
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  |  Configuration" -ForegroundColor White
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  |  DNS Provider: $DnsProvider" -ForegroundColor DarkCyan
    Write-Host "  |  Domain      : $playerAddr" -ForegroundColor DarkCyan
    Write-Host "  |  SRV Record  : $SrvRecordName.$RootDomain" -ForegroundColor DarkCyan
    Write-Host "  |  Local Port  : $LocalPort" -ForegroundColor DarkCyan
    Write-Host "  |  Hot-Swap    : ${HotSwapMinute} min" -ForegroundColor DarkCyan
    Write-Host "  |  DNS TTL     : ${TTL}s" -ForegroundColor DarkCyan
    Write-Host "  |  SRV Pri/Wgt : Pri: ${Priority}, Wgt: ${Weight}" -ForegroundColor DarkCyan
    Write-Host "  |  Log File    : $(Get-CurrentLogFile)" -ForegroundColor DarkCyan
    Write-Host "  |  Retention   : ${LogRetentionDays} days" -ForegroundColor DarkCyan
    Write-Host "  -------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-StatusDisplay {
    param([string]$TunnelAddr, [int]$TunnelPort)
    $up = Get-UptimeString
    $playerAddr = Get-PlayerAddress -Srv $SrvRecordName -Domain $RootDomain
    Write-Host ""
    Write-Host "  -------------------------------------------------------" -ForegroundColor Green
    Write-Host "  |  TunnelKeeper Gateway - LIVE STATUS" -ForegroundColor White
    Write-Host "  -------------------------------------------------------" -ForegroundColor Green
    Write-Host "  |  Player Address : $playerAddr" -ForegroundColor Yellow
    Write-Host "  |  Tunnel Target  : ${TunnelAddr}:${TunnelPort}" -ForegroundColor Cyan
    Write-Host "  |  Local Server   : localhost:$LocalPort" -ForegroundColor DarkCyan
    Write-Host "  |  DNS Status     : Active on $DnsProvider" -ForegroundColor Green
    Write-Host "  |  Service Uptime : $up" -ForegroundColor DarkGray
    Write-Host "  -------------------------------------------------------" -ForegroundColor Green
    Write-Host ""
}

function Update-DnsSRV {
    param([string]$TargetHost, [int]$TargetPort)
    if ($DnsProvider -match "cloudflare") {
        return Update-CloudflareSRV -RootDomain $RootDomain -SrvRecordName $SrvRecordName `
            -TargetHost $TargetHost -TargetPort $TargetPort -Priority $Priority -Weight $Weight `
            -TTL $TTL -CloudflareApiToken $CloudflareApiToken -CloudflareZoneId $CloudflareZoneId
    } else {
        return Update-HostingerSRV -RootDomain $RootDomain -SrvRecordName $SrvRecordName `
            -TargetHost $TargetHost -TargetPort $TargetPort -Priority $Priority -Weight $Weight `
            -TTL $TTL -HostingerToken $HostingerToken
    }
}

function Test-DnsPropagation {
    param([string]$ExpectedHost, [int]$ExpectedPort)
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
            Write-Log "[DNS] $DnsProvider updated. Propagating... (current: $(($records[0].Target).TrimEnd('.')):$($records[0].Port))" "DarkGray"
        }
    } catch {}
    return $false
}

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
    $psi.EnvironmentVariables["SSH_ASKPASS"]         = "`"$env:SSH_ASKPASS`""
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
            try { $s.output.AppendLine($EventArgs.Data) } finally { [System.Threading.Monitor]::Exit($s.lockObj) }
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
            try { $s.output.AppendLine($EventArgs.Data) } finally { [System.Threading.Monitor]::Exit($s.lockObj) }
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
    }

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

# ------------------------------------------------------------
# DUPLICATE INSTANCE GUARD & FORCE RESTART
# ------------------------------------------------------------
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
    $hasMutex = $false
} catch [System.Threading.AbandonedMutexException] {
    $hasMutex = $true
} catch {
    $hasMutex = $false
}

if (-not $hasMutex) {
    $schedTask = Get-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    $logPath = Get-CurrentLogFile
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
    } else {
        Write-Host "  =======================================================" -ForegroundColor Red
        Write-Host "     ERROR: Another instance is already running!         " -ForegroundColor Red
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
    $askPassScript = Join-Path $env:TEMP "pinggy_askpass.cmd"
    Set-Content -Path $askPassScript -Value "echo." -Encoding ASCII
    $env:SSH_ASKPASS         = "`"$askPassScript`""
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY             = ":0"

    Rotate-Logs -RetentionDays $LogRetentionDays

    Show-Banner
    Show-ConfigDisplay

    Write-Log "Gateway started. Logs saved to: $(Get-CurrentLogFile)" "DarkGray"

    if (-not (Test-LocalServer -Port $LocalPort)) {
        Write-Log "[Pre-flight] Notice: Local Minecraft server not detected on port $LocalPort yet. Proceeding..." "Yellow"
    } else {
        Write-Log "[Pre-flight] Local Minecraft server is online on port $LocalPort." "Green"
    }

    # ------------------------------------------------------------
    # MAIN HOT-SWAP LOOP
    # ------------------------------------------------------------
    while ($true) {
        $script:CycleCount++
        Write-Host ""
        Write-Host "  =======================================================" -ForegroundColor DarkGray
        Write-Log "[Cycle #$($script:CycleCount)] Starting Pinggy tunnel for localhost:$LocalPort ..." "Cyan"

        $tunnel = Start-Tunnel -Label "Tunnel"

        if (-not $tunnel.success) {
            Write-Log "[Tunnel] Failed to establish tunnel. Retrying in 10 seconds..." "Red"
            Stop-Tunnel $tunnel
            Start-Sleep -Seconds 10
            continue
        }

        $currentOutput = $tunnel.state.output.ToString()
        if ($currentOutput.Length -gt 0) {
            Write-Host $currentOutput -NoNewline
            try { Add-Content -Path (Get-CurrentLogFile) -Value $currentOutput -ErrorAction SilentlyContinue } catch {}
        }
        $lastOutputLen = $currentOutput.Length

        Write-Log "[Tunnel] Detected: $($tunnel.state.tunnelHost):$($tunnel.state.tunnelPort)" "Cyan"
        $dnsUpdated = Update-DnsSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort

        if ($dnsUpdated) {
            Test-DnsPropagation -ExpectedHost $tunnel.state.tunnelHost -ExpectedPort $tunnel.state.tunnelPort | Out-Null
            Show-StatusDisplay -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
        }

        $hotSwapStarted     = $false
        $lastHotSwapAttempt = $null
        $lastDnsRetry       = Get-Date
        $pendingOldTunnel   = $null
        $swapTime           = $null

        while (-not $tunnel.proc.HasExited) {
            Start-Sleep -Milliseconds 1000

            $currentOutput = ""
            [System.Threading.Monitor]::Enter($tunnel.state.lockObj)
            try { $currentOutput = $tunnel.state.output.ToString() } finally { [System.Threading.Monitor]::Exit($tunnel.state.lockObj) }
            if ($currentOutput.Length -gt $lastOutputLen) {
                $newText = $currentOutput.Substring($lastOutputLen)
                Write-Host $newText -NoNewline
                try { Add-Content -Path (Get-CurrentLogFile) -Value $newText -ErrorAction SilentlyContinue } catch {}
                $lastOutputLen = $currentOutput.Length
            }

            if ((-not $dnsUpdated) -and $tunnel.state.urlFound) {
                if (((Get-Date) - $lastDnsRetry).TotalSeconds -ge 30) {
                    Write-Log "[DNS] Retrying DNS update..." "Yellow"
                    $dnsUpdated = Update-DnsSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort
                    $lastDnsRetry = Get-Date
                    if ($dnsUpdated) {
                        Test-DnsPropagation -ExpectedHost $tunnel.state.tunnelHost -ExpectedPort $tunnel.state.tunnelPort | Out-Null
                        Show-StatusDisplay -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
                    }
                }
            }

            if ($null -ne $pendingOldTunnel) {
                $oldExited     = $pendingOldTunnel.proc.HasExited
                $safetyTimeout = (((Get-Date) - $swapTime).TotalSeconds -ge 600)
                if ($oldExited -or $safetyTimeout) {
                    Write-Log "[HotSwap] Old tunnel expired/timed out. Cleaned up." "DarkGray"
                    Stop-Tunnel $pendingOldTunnel
                    $pendingOldTunnel = $null
                }
            }

            $elapsed = ((Get-Date) - $tunnel.startTime).TotalMinutes
            $canRetrySwap = ($null -eq $lastHotSwapAttempt) -or (((Get-Date) - $lastHotSwapAttempt).TotalSeconds -ge 60)
            if ($elapsed -ge $HotSwapMinute -and $elapsed -lt 68 -and -not $hotSwapStarted -and $canRetrySwap) {
                $hotSwapStarted = $true
                Write-Host ""
                Write-Host "  - - - - - - - - -  HOT-SWAP  - - - - - - - - - -" -ForegroundColor Yellow
                Write-Log "[HotSwap] Tunnel at $([math]::Round($elapsed,1)) min. Pre-starting replacement..." "Cyan"

                $newTunnel = Start-Tunnel -Label "HotSwap"

                if ($newTunnel.success) {
                    Write-Log "[HotSwap] New tunnel: $($newTunnel.state.tunnelHost):$($newTunnel.state.tunnelPort)" "Cyan"
                    Write-Log "[HotSwap] Updating DNS to new tunnel..." "Cyan"
                    $dnsUpdated = Update-DnsSRV -TargetHost $newTunnel.state.tunnelHost -TargetPort $newTunnel.state.tunnelPort
                    if ($dnsUpdated) {
                        Test-DnsPropagation -ExpectedHost $newTunnel.state.tunnelHost -ExpectedPort $newTunnel.state.tunnelPort | Out-Null
                    }

                    $pendingOldTunnel = $tunnel
                    $swapTime = Get-Date

                    $tunnel = $newTunnel
                    $hotSwapStarted = $false
                    $lastHotSwapAttempt = $null
                    $lastOutputLen = 0
                    $lastDnsRetry = Get-Date
                    $script:CycleCount++
                    $script:SwapCount++

                    Write-Log "[HotSwap] Swap complete! (Swap #$($script:SwapCount))" "Green"
                    if ($dnsUpdated) {
                        Show-StatusDisplay -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
                    }
                } else {
                    Write-Log "[HotSwap] Failed to pre-start replacement. Retrying in 60s..." "Yellow"
                    Stop-Tunnel $newTunnel
                    $lastHotSwapAttempt = Get-Date
                    $hotSwapStarted = $false
                }
            }

            if ($elapsed -gt 75) {
                Write-Log "[Watchdog] Tunnel alive for $([math]::Round($elapsed,1)) min. Force-killing." "Yellow"
                try { $tunnel.proc.Kill() } catch {}
                break
            }
        }

        Stop-Tunnel $tunnel
        if ($null -ne $pendingOldTunnel) {
            Stop-Tunnel $pendingOldTunnel
            $pendingOldTunnel = $null
        }

        $up = Get-UptimeString
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
