# ============================================================
# TheRealNeighbors Gateway v3
# Dynamic Tunnel & DNS Service
# ============================================================
#
# What this does:
#   1. Starts a free Pinggy TCP tunnel pointed at your Minecraft server
#   2. Reads the public address/port Pinggy assigns
#   3. Updates your Hostinger SRV record so your domain always
#      points at the current tunnel
#   4. Uses HOT-SWAP to pre-start a replacement tunnel before
#      the old one expires, achieving near-zero downtime
#
# Requires: OpenSSH client (built into Windows 10/11), PowerShell
# ============================================================

# ---------------------- CONFIG ----------------------
$HostingerToken = ""
$EnvPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $EnvPath) {
    foreach ($line in Get-Content $EnvPath) {
        if ($line -match '^HostingerToken=(.*)') {
            $HostingerToken = $matches[1].Trim()
        }
    }
}
if ([string]::IsNullOrEmpty($HostingerToken)) {
    Write-Host "Error: HostingerToken not found. Please create a .env file with HostingerToken=YOUR_TOKEN" -ForegroundColor Red
    exit 1
}
$RootDomain     = "therealneighbors.online"
$SrvRecordName  = "_minecraft._tcp.play"
$LocalPort      = 25566
$Priority       = 0
$Weight         = 5
$TTL            = 60
$HotSwapMinute  = 55
# ----------------------------------------------------

# ============================================================
# LOGGING & STATE
# ============================================================

# Disable QuickEdit Mode to prevent accidental freezing when clicking the console
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
[ConsoleHelper]::DisableQuickEdit()

$script:LogDir = Join-Path $env:USERPROFILE "TRN_Gateway_Logs"
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}
$script:LogFile     = Join-Path $script:LogDir ("gateway_$(Get-Date -Format 'yyyy-MM-dd').log")
$script:CycleCount  = 0
$script:ScriptStart = Get-Date

# ============================================================
# DISPLAY & LOGGING HELPERS
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Write-Display {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host $Message -ForegroundColor $Color
    try { Add-Content -Path $script:LogFile -Value $Message -ErrorAction SilentlyContinue } catch {}
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
    Write-Display "         _______ _____  _   _                    " "Cyan"
    Write-Display "        |__   __|  __ \| \ | |                   " "Cyan"
    Write-Display "           | |  | |__) |  \| |                   " "Cyan"
    Write-Display "           | |  |  _  /| . ` |                   " "Cyan"
    Write-Display "           | |  | | \ \| |\  |                   " "Cyan"
    Write-Display "           |_|  |_|  \_\_| \_|                   " "Cyan"
    Write-Display "                                                         " "Cyan"
    Write-Display "         TheRealNeighbors Gateway v3                     " "White"
    Write-Display "         Dynamic Tunnel & DNS Service                    " "DarkCyan"
    Write-Display "                                                         " "Cyan"
    Write-Display "  =======================================================" "Cyan"
    Write-Display ""
}

function Show-Config {
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display "  |  Configuration" "White"
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display "  |  Domain      : play.$RootDomain" "DarkCyan"
    Write-Display "  |  Local Port  : $LocalPort" "DarkCyan"
    Write-Display "  |  Hot-Swap    : ${HotSwapMinute} min" "DarkCyan"
    Write-Display "  |  DNS TTL     : ${TTL}s" "DarkCyan"
    Write-Display "  |  Log File    : $($script:LogFile)" "DarkCyan"
    Write-Display "  -------------------------------------------------------" "DarkGray"
    Write-Display ""
}

function Show-Status {
    param([string]$TunnelAddr, [int]$TunnelPort)
    $up = Get-UptimeString
    Write-Display ""
    Write-Display "  -------------------------------------------------------" "Green"
    Write-Display "  |  TUNNEL ACTIVE" "Green"
    Write-Display "  -------------------------------------------------------" "Green"
    Write-Display "  |  Address  : ${TunnelAddr}:${TunnelPort}" "White"
    Write-Display "  |  Domain   : play.$RootDomain" "White"
    Write-Display "  |  Swap In  : ~$HotSwapMinute min" "White"
    Write-Display "  |  Cycle    : #$($script:CycleCount)  |  Uptime: $up" "White"
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
            Write-Log "[DNS] PUT attempt $attempt/$maxRetries failed: $_" "Red"
            if ($attempt -lt $maxRetries) {
                Write-Log "[DNS] Retrying in 5 seconds..." "Yellow"
                Start-Sleep -Seconds 5
            } else {
                Write-Log "[DNS] All $maxRetries attempts failed." "Red"
            }
        }
    }
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
        tunnelHost = ""
        tunnelPort = 0
        urlFound   = $false
    })

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "ssh"
    $psi.Arguments              = "-o StrictHostKeyChecking=no -p 443 -R0:localhost:$LocalPort tcp@a.pinggy.io"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.EnvironmentVariables["SSH_ASKPASS"]        = $env:SSH_ASKPASS
    $psi.EnvironmentVariables["SSH_ASKPASS_REQUIRE"] = "force"
    $psi.EnvironmentVariables["DISPLAY"]             = ":0"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $tunnel.proc = $proc

    $tunnel.outHandler = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -MessageData $tunnel.state -Action {
        if ($EventArgs.Data) {
            $s = $Event.MessageData
            if ($EventArgs.Data -match "^\s*RB: \d+") { return }
            $s.output.AppendLine($EventArgs.Data)
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
            if ($EventArgs.Data -match "^\s*RB: \d+") { return }
            $s.output.AppendLine($EventArgs.Data)
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

    # Send blank password lines
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Seconds 2
        try {
            if (-not $proc.HasExited) {
                $proc.StandardInput.WriteLine("")
                $proc.StandardInput.Flush()
            } else { break }
        } catch { break }
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
$mutex = New-Object System.Threading.Mutex($false, "Global\TRN_MinecraftGateway")
if (-not $mutex.WaitOne(0)) {
    Write-Host ""
    Write-Host "  ===============================================" -ForegroundColor Red
    Write-Host "     ERROR: Another instance is already running! " -ForegroundColor Red
    Write-Host "     Close the other PowerShell window first.    " -ForegroundColor Red
    Write-Host "  ===============================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

try {
    # SSH_ASKPASS setup
    $askPassScript = Join-Path $env:TEMP "pinggy_askpass.cmd"
    Set-Content -Path $askPassScript -Value "echo." -Encoding ASCII
    $env:SSH_ASKPASS         = $askPassScript
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY             = ":0"

    # Startup display
    Show-Banner
    Show-Config

    Write-Log "Gateway started. Logs saved to: $($script:LogFile)" "DarkGray"

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
            try { Add-Content -Path $script:LogFile -Value $currentOutput -ErrorAction SilentlyContinue } catch {}
        }
        $lastOutputLen = $currentOutput.Length

        Write-Log "[Tunnel] Detected: $($tunnel.state.tunnelHost):$($tunnel.state.tunnelPort)" "Cyan"
        $dnsUpdated = Update-HostingerSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort

        if ($dnsUpdated) {
            Show-Status -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
        }

        $hotSwapStarted   = $false
        $lastDnsRetry     = Get-Date
        $pendingOldTunnel = $null
        $swapTime         = $null

        # ---- Monitoring Loop ----
        while (-not $tunnel.proc.HasExited) {
            Start-Sleep -Milliseconds 1000

            # Print any new output
            $currentOutput = $tunnel.state.output.ToString()
            if ($currentOutput.Length -gt $lastOutputLen) {
                $newText = $currentOutput.Substring($lastOutputLen)
                Write-Host $newText -NoNewline
                try { Add-Content -Path $script:LogFile -Value $newText -ErrorAction SilentlyContinue } catch {}
                $lastOutputLen = $currentOutput.Length
            }

            # DNS retry every 30 seconds if last update failed
            if ((-not $dnsUpdated) -and $tunnel.state.urlFound) {
                $sinceLast = ((Get-Date) - $lastDnsRetry).TotalSeconds
                if ($sinceLast -ge 30) {
                    Write-Log "[DNS] Retrying DNS update..." "Yellow"
                    $dnsUpdated = Update-HostingerSRV -TargetHost $tunnel.state.tunnelHost -TargetPort $tunnel.state.tunnelPort
                    $lastDnsRetry = Get-Date
                    if ($dnsUpdated) {
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
            if ($elapsed -ge $HotSwapMinute -and -not $hotSwapStarted) {
                $hotSwapStarted = $true
                Write-Display ""
                Write-Display "  - - - - - - - - -  HOT-SWAP  - - - - - - - - - -" "Yellow"
                Write-Log "[HotSwap] Tunnel at $([math]::Round($elapsed,1)) min. Pre-starting replacement..." "Cyan"

                $newTunnel = Start-Tunnel -Label "HotSwap"

                if ($newTunnel.success) {
                    Write-Log "[HotSwap] New tunnel: $($newTunnel.state.tunnelHost):$($newTunnel.state.tunnelPort)" "Cyan"
                    Write-Log "[HotSwap] Updating DNS to new tunnel..." "Cyan"
                    $dnsUpdated = Update-HostingerSRV -TargetHost $newTunnel.state.tunnelHost -TargetPort $newTunnel.state.tunnelPort

                    # Keep old tunnel alive until Pinggy expires it
                    $pendingOldTunnel = $tunnel
                    $swapTime = Get-Date

                    # Switch monitoring to new tunnel
                    $tunnel = $newTunnel
                    $hotSwapStarted = $false
                    $lastOutputLen = 0
                    $lastDnsRetry = Get-Date

                    Write-Log "[HotSwap] Swap complete! Old tunnel stays alive until Pinggy expires it." "Green"
                    if ($dnsUpdated) {
                        Show-Status -TunnelAddr $tunnel.state.tunnelHost -TunnelPort $tunnel.state.tunnelPort
                    }
                } else {
                    Write-Log "[HotSwap] Failed to pre-start replacement. Will restart when tunnel dies." "Yellow"
                    Stop-Tunnel $newTunnel
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
        $currentOutput = $tunnel.state.output.ToString()
        if ($currentOutput.Length -gt $lastOutputLen) {
            $finalText = $currentOutput.Substring($lastOutputLen)
            Write-Host $finalText -NoNewline
            try { Add-Content -Path $script:LogFile -Value $finalText -ErrorAction SilentlyContinue } catch {}
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
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
