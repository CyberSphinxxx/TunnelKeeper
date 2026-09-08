<#
====================================================================
 TunnelKeeper - Core Network & Process Diagnostics Module
 Tests local port availability, mutex locks, and SSH processes
====================================================================
#>

function Test-LocalServer {
    param([int]$Port = 25565)

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

function Get-RunningTunnels {
    param([int]$Port = 0)

    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io" -or ($Port -gt 0 -and $_.CommandLine -match "$Port"))
    }
    return $procs
}

function Get-GatewayMutexState {
    param([string]$MutexName = "Global\TunnelKeeper_Gateway")

    try {
        $testMutex = [System.Threading.Mutex]::OpenExisting($MutexName)
        if ($testMutex) {
            $testMutex.Dispose()
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Show-ServiceStatus {
    param([hashtable]$Config)

    $rootDomain    = $Config["RootDomain"]
    $srvRecordName = $Config["SrvRecordName"]
    $localPort     = $Config["LocalPort"]

    $schedTask = Get-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    $taskRunning = ($schedTask -and $schedTask.State -eq "Running")

    $mutexLocked = Get-GatewayMutexState
    $sshProcs = Get-RunningTunnels -Port $localPort
    $localServerUp = Test-LocalServer -Port $localPort

    $liveDns = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($rootDomain) -and $rootDomain -notmatch 'example\.com|yourdomain\.com') {
            $recs = Resolve-DnsName -Name "$srvRecordName.$rootDomain" -Type SRV -ErrorAction SilentlyContinue
            if ($recs) {
                $liveDns = "$(($recs[0].Target).TrimEnd('.')):$($recs[0].Port)"
            }
        }
    } catch {}

    Write-Host ""
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host "   TunnelKeeper Gateway - Service Diagnostics Status     " -ForegroundColor Cyan
    Write-Host "  =======================================================" -ForegroundColor Cyan
    Write-Host ""

    $srvStatus = if ($localServerUp) { "[UP] Listening on port $localPort" } else { "[DOWN] Nothing listening on port $localPort" }
    $srvColor  = if ($localServerUp) { "Green" } else { "Red" }
    Write-Host "  Minecraft Server : " -NoNewline; Write-Host $srvStatus -ForegroundColor $srvColor

    $mutStatus = if ($mutexLocked) { "[LOCKED] Process running" } else { "[FREE] Idle" }
    $mutColor  = if ($mutexLocked) { "Green" } else { "DarkGray" }
    Write-Host "  Gateway Mutex    : " -NoNewline; Write-Host $mutStatus -ForegroundColor $mutColor

    $tunCount  = if ($sshProcs) { @($sshProcs).Count } else { 0 }
    $tunStatus = if ($tunCount -gt 0) { "[ACTIVE] $tunCount tunnel process(es)" } else { "[INACTIVE] No tunnels" }
    $tunColor  = if ($tunCount -gt 0) { "Green" } else { "Yellow" }
    Write-Host "  Active Tunnels   : " -NoNewline; Write-Host $tunStatus -ForegroundColor $tunColor

    $dnsStatus = if ($liveDns) { "[RESOLVED] $liveDns" } else { "[NOT FOUND] No SRV record found" }
    $dnsColor  = if ($liveDns) { "Green" } else { "Yellow" }
    Write-Host "  Public SRV Record: " -NoNewline; Write-Host $dnsStatus -ForegroundColor $dnsColor

    Write-Host ""
}
