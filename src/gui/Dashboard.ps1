<#
====================================================================
 TunnelKeeper - GUI Dashboard Controller Module
 Binds WPF controls, handles user actions, and streams live stats
====================================================================
#>

function Initialize-DashboardController {
    param(
        [Parameter(Mandatory=$true)]$Window,
        [Parameter(Mandatory=$true)][string]$EnvFilePath,
        [Parameter(Mandatory=$true)][string]$CoreScriptPath,
        $NotifyIcon
    )

    # ------------------------------------------------------------
    # BIND CONTROLS
    # ------------------------------------------------------------
    $NavTabDashboard            = $Window.FindName("NavTabDashboard")
    $NavTabSettings             = $Window.FindName("NavTabSettings")
    $NavTabLogs                 = $Window.FindName("NavTabLogs")

    $PanelDashboard             = $Window.FindName("PanelDashboard")
    $PanelSettings              = $Window.FindName("PanelSettings")
    $PanelLogs                  = $Window.FindName("PanelLogs")

    $BadgeStatus                = $Window.FindName("BadgeStatus")
    $TxtBadgeStatus             = $Window.FindName("TxtBadgeStatus")
    $TxtProviderLabel           = $Window.FindName("TxtProviderLabel")
    $TxtLocalServerLabel        = $Window.FindName("TxtLocalServerLabel")
    $TxtPublicDomain            = $Window.FindName("TxtPublicDomain")
    $TxtLiveEndpoint            = $Window.FindName("TxtLiveEndpoint")
    $BtnCopyDomain              = $Window.FindName("BtnCopyDomain")
    $TxtSwapInfo                = $Window.FindName("TxtSwapInfo")
    $TxtCycleCount              = $Window.FindName("TxtCycleCount")
    $TxtUptime                  = $Window.FindName("TxtUptime")
    $BtnToggleService           = $Window.FindName("BtnToggleService")
    $BtnRestartService          = $Window.FindName("BtnRestartService")
    $TxtDashboardLogs           = $Window.FindName("TxtDashboardLogs")
    $TxtLogFileSummary          = $Window.FindName("TxtLogFileSummary")
    $BtnMinimizeTray            = $Window.FindName("BtnMinimizeTray")

    $SettingsNoticeBanner       = $Window.FindName("SettingsNoticeBanner")
    $TxtSettingsNotice          = $Window.FindName("TxtSettingsNotice")
    $RadioHostinger             = $Window.FindName("RadioHostinger")
    $RadioCloudflare            = $Window.FindName("RadioCloudflare")
    $BlockHostinger             = $Window.FindName("BlockHostinger")
    $BlockCloudflare            = $Window.FindName("BlockCloudflare")
    $TxtHostingerToken          = $Window.FindName("TxtHostingerToken")
    $TxtHostingerTokenVisible   = $Window.FindName("TxtHostingerTokenVisible")
    $BtnToggleHostingerToken    = $Window.FindName("BtnToggleHostingerToken")
    $TxtCloudflareToken         = $Window.FindName("TxtCloudflareToken")
    $TxtCloudflareTokenVisible  = $Window.FindName("TxtCloudflareTokenVisible")
    $BtnToggleCloudflareToken   = $Window.FindName("BtnToggleCloudflareToken")
    $TxtCloudflareZoneId        = $Window.FindName("TxtCloudflareZoneId")
    $TxtRootDomain              = $Window.FindName("TxtRootDomain")
    $TxtSrvRecordName           = $Window.FindName("TxtSrvRecordName")
    $TxtLocalPort               = $Window.FindName("TxtLocalPort")
    $TxtHotSwapMinute           = $Window.FindName("TxtHotSwapMinute")
    $TxtPriority                = $Window.FindName("TxtPriority")
    $TxtWeight                  = $Window.FindName("TxtWeight")
    $TxtTTL                     = $Window.FindName("TxtTTL")
    $TxtLogRetention            = $Window.FindName("TxtLogRetention")
    $BtnSaveSettings            = $Window.FindName("BtnSaveSettings")

    $ChkAutoScroll              = $Window.FindName("ChkAutoScroll")
    $BtnClearLogView            = $Window.FindName("BtnClearLogView")
    $BtnOpenLogFile             = $Window.FindName("BtnOpenLogFile")
    $BtnOpenLogFolder           = $Window.FindName("BtnOpenLogFolder")
    $TxtFullLogPath             = $Window.FindName("TxtFullLogPath")
    $TxtFullLogs                = $Window.FindName("TxtFullLogs")

    $envConfig = Get-TunnelKeeperConfig -EnvPath $EnvFilePath

    if ($envConfig["HostingerToken"]) { Register-MaskToken $envConfig["HostingerToken"] }
    if ($envConfig["CloudflareApiToken"]) { Register-MaskToken $envConfig["CloudflareApiToken"] }

    if ($envConfig["DnsProvider"] -match "cloudflare") {
        $RadioCloudflare.IsChecked = $true
        $BlockCloudflare.Visibility = "Visible"
        $BlockHostinger.Visibility  = "Collapsed"
    } else {
        $RadioHostinger.IsChecked  = $true
        $BlockHostinger.Visibility = "Visible"
        $BlockCloudflare.Visibility = "Collapsed"
    }

    $TxtHostingerToken.Password        = $envConfig["HostingerToken"]
    $TxtHostingerTokenVisible.Text     = $envConfig["HostingerToken"]
    $TxtCloudflareToken.Password       = $envConfig["CloudflareApiToken"]
    $TxtCloudflareTokenVisible.Text    = $envConfig["CloudflareApiToken"]
    $TxtCloudflareZoneId.Text          = $envConfig["CloudflareZoneId"]
    $TxtRootDomain.Text                = $envConfig["RootDomain"]
    $TxtSrvRecordName.Text             = $envConfig["SrvRecordName"]
    $TxtLocalPort.Text                 = [string]$envConfig["LocalPort"]
    $TxtHotSwapMinute.Text             = [string]$envConfig["HotSwapMinute"]
    $TxtPriority.Text                  = [string]$envConfig["Priority"]
    $TxtWeight.Text                    = [string]$envConfig["Weight"]
    $TxtTTL.Text                       = [string]$envConfig["TTL"]
    $TxtLogRetention.Text              = [string]$envConfig["LogRetentionDays"]

    $TxtPublicDomain.Text = Get-PlayerAddress -Srv $envConfig["SrvRecordName"] -Domain $envConfig["RootDomain"]

    # ------------------------------------------------------------
    # TAB NAVIGATION
    # ------------------------------------------------------------
    $setActiveTab = {
        param([string]$tabName)
        $PanelDashboard.Visibility = "Collapsed"
        $PanelSettings.Visibility  = "Collapsed"
        $PanelLogs.Visibility      = "Collapsed"

        $NavTabDashboard.Background = "Transparent"
        $NavTabDashboard.Foreground = "#94A3B8"
        $NavTabSettings.Background  = "Transparent"
        $NavTabSettings.Foreground  = "#94A3B8"
        $NavTabLogs.Background      = "Transparent"
        $NavTabLogs.Foreground      = "#94A3B8"

        switch ($tabName) {
            "Dashboard" {
                $PanelDashboard.Visibility  = "Visible"
                $NavTabDashboard.Background = "#0284C7"
                $NavTabDashboard.Foreground = "#FFFFFF"
            }
            "Settings" {
                $PanelSettings.Visibility  = "Visible"
                $NavTabSettings.Background = "#0284C7"
                $NavTabSettings.Foreground = "#FFFFFF"
            }
            "Logs" {
                $PanelLogs.Visibility  = "Visible"
                $NavTabLogs.Background = "#0284C7"
                $NavTabLogs.Foreground = "#FFFFFF"
            }
        }
    }

    $NavTabDashboard.Add_Click({ & $setActiveTab "Dashboard" })
    $NavTabSettings.Add_Click({ & $setActiveTab "Settings" })
    $NavTabLogs.Add_Click({ & $setActiveTab "Logs" })

    # Provider Radio Toggles
    $RadioHostinger.Add_Checked({
        $BlockHostinger.Visibility  = "Visible"
        $BlockCloudflare.Visibility = "Collapsed"
    })
    $RadioCloudflare.Add_Checked({
        $BlockCloudflare.Visibility = "Visible"
        $BlockHostinger.Visibility  = "Collapsed"
    })

    # Password Visibility Toggles
    $BtnToggleHostingerToken.Add_Click({
        if ($TxtHostingerTokenVisible.Visibility -eq "Visible") {
            $TxtHostingerToken.Password = $TxtHostingerTokenVisible.Text
            $TxtHostingerTokenVisible.Visibility = "Collapsed"
            $TxtHostingerToken.Visibility = "Visible"
            $BtnToggleHostingerToken.Content = "Show"
        } else {
            $TxtHostingerTokenVisible.Text = $TxtHostingerToken.Password
            $TxtHostingerToken.Visibility = "Collapsed"
            $TxtHostingerTokenVisible.Visibility = "Visible"
            $BtnToggleHostingerToken.Content = "Hide"
        }
    })

    $BtnToggleCloudflareToken.Add_Click({
        if ($TxtCloudflareTokenVisible.Visibility -eq "Visible") {
            $TxtCloudflareToken.Password = $TxtCloudflareTokenVisible.Text
            $TxtCloudflareTokenVisible.Visibility = "Collapsed"
            $TxtCloudflareToken.Visibility = "Visible"
            $BtnToggleCloudflareToken.Content = "Show"
        } else {
            $TxtCloudflareTokenVisible.Text = $TxtCloudflareToken.Password
            $TxtCloudflareToken.Visibility = "Collapsed"
            $TxtCloudflareTokenVisible.Visibility = "Visible"
            $BtnToggleCloudflareToken.Content = "Hide"
        }
    })

    # ------------------------------------------------------------
    # SETTINGS NOTICE & SAVING
    # ------------------------------------------------------------
    $showNotice = {
        param([string]$Msg, [string]$Type = "Success")
        $SettingsNoticeBanner.Visibility = "Visible"
        $TxtSettingsNotice.Text = $Msg
        if ($Type -eq "Error") {
            $SettingsNoticeBanner.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7F1D1D")
            $TxtSettingsNotice.Foreground    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        } else {
            $SettingsNoticeBanner.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
            $TxtSettingsNotice.Foreground    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
        }

        $timerNotice = New-Object System.Windows.Threading.DispatcherTimer
        $timerNotice.Interval = [TimeSpan]::FromSeconds(5)
        $timerNotice.Add_Tick({
            $SettingsNoticeBanner.Visibility = "Collapsed"
            $timerNotice.Stop()
        })
        $timerNotice.Start()
    }

    $BtnSaveSettings.Add_Click({
        $p = if ($RadioCloudflare.IsChecked) { "Cloudflare" } else { "Hostinger" }
        $hToken = if ($TxtHostingerTokenVisible.Visibility -eq "Visible") { $TxtHostingerTokenVisible.Text.Trim() } else { $TxtHostingerToken.Password.Trim() }
        $cToken = if ($TxtCloudflareTokenVisible.Visibility -eq "Visible") { $TxtCloudflareTokenVisible.Text.Trim() } else { $TxtCloudflareToken.Password.Trim() }

        if ($p -eq "Hostinger" -and [string]::IsNullOrWhiteSpace($hToken)) {
            & $showNotice "Hostinger API Token cannot be empty." "Error"
            return
        }
        if ($p -eq "Cloudflare" -and [string]::IsNullOrWhiteSpace($cToken)) {
            & $showNotice "Cloudflare API Token cannot be empty." "Error"
            return
        }

        $domain = $TxtRootDomain.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($domain) -or $domain -in @("yourdomain.com", "example.com")) {
            & $showNotice "Please enter your own valid Root Domain (e.g. yourdomain.com)." "Error"
            return
        }

        $srvName = $TxtSrvRecordName.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($srvName)) {
            & $showNotice "SRV Record Name cannot be empty (e.g. _minecraft._tcp.play)." "Error"
            return
        }

        $port = 0
        if (-not [int]::TryParse($TxtLocalPort.Text.Trim(), [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            & $showNotice "Local Port must be a valid port number (1 - 65535)." "Error"
            return
        }

        $swapMin = 0
        if (-not [int]::TryParse($TxtHotSwapMinute.Text.Trim(), [ref]$swapMin) -or $swapMin -lt 5 -or $swapMin -gt 59) {
            & $showNotice "Hot-Swap Interval must be between 5 and 59 minutes." "Error"
            return
        }

        $priorityVal = 0
        if (-not [int]::TryParse($TxtPriority.Text.Trim(), [ref]$priorityVal) -or $priorityVal -lt 0 -or $priorityVal -gt 65535) {
            & $showNotice "SRV Priority must be an integer between 0 and 65535." "Error"
            return
        }

        $weightVal = 5
        if (-not [int]::TryParse($TxtWeight.Text.Trim(), [ref]$weightVal) -or $weightVal -lt 0 -or $weightVal -gt 65535) {
            & $showNotice "SRV Weight must be an integer between 0 and 65535." "Error"
            return
        }

        $ttlVal = 0
        if (-not [int]::TryParse($TxtTTL.Text.Trim(), [ref]$ttlVal) -or $ttlVal -lt 1) {
            & $showNotice "DNS TTL must be a positive number of seconds (e.g. 60)." "Error"
            return
        }

        $retentionVal = 0
        if (-not [int]::TryParse($TxtLogRetention.Text.Trim(), [ref]$retentionVal) -or $retentionVal -lt 1) {
            & $showNotice "Log Retention must be at least 1 day." "Error"
            return
        }

        $newCfg = @{
            DnsProvider        = $p
            HostingerToken     = $hToken
            CloudflareApiToken = $cToken
            CloudflareZoneId   = $TxtCloudflareZoneId.Text.Trim()
            RootDomain         = $domain
            SrvRecordName      = $srvName
            LocalPort          = $port
            HotSwapMinute      = $swapMin
            TTL                = $ttlVal
            Priority           = $priorityVal
            Weight             = $weightVal
            LogRetentionDays   = $retentionVal
        }

        Save-TunnelKeeperConfig -Config $newCfg -EnvPath $EnvFilePath
        if ($hToken) { Register-MaskToken $hToken }
        if ($cToken) { Register-MaskToken $cToken }
        $TxtPublicDomain.Text = Get-PlayerAddress -Srv $newCfg["SrvRecordName"] -Domain $newCfg["RootDomain"]

        if (Get-ServiceState) {
            & $showNotice "Settings saved! Restart Tunnel Gateway to apply new configuration." "Success"
        } else {
            & $showNotice "Settings saved to .env! (Provider: $p)" "Success"
        }
    })

    # ------------------------------------------------------------
    # CLIPBOARD & LOG HELPERS
    # ------------------------------------------------------------
    $BtnCopyDomain.Add_Click({
        $currentAddr = $TxtPublicDomain.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($currentAddr) -or $currentAddr -like "*Configure domain*" -or $currentAddr -like "*<Domain*") {
            & $showNotice "Please configure your domain in Settings first." "Error"
            & $setActiveTab "Settings"
            return
        }
        [System.Windows.Clipboard]::SetText($currentAddr)
        $BtnCopyDomain.Content = "Copied!"
        $BtnCopyDomain.Background = "#059669"
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(2)
        $t.Add_Tick({
            $BtnCopyDomain.Content = "Copy Server Address"
            $BtnCopyDomain.Background = "#0284C7"
            $t.Stop()
        })
        $t.Start()
    })

    $BtnClearLogView.Add_Click({
        $TxtFullLogs.Text = ""
        $TxtDashboardLogs.Text = ""
    })

    $BtnOpenLogFile.Add_Click({
        $logFile = Get-CurrentLogFile
        if (Test-Path $logFile) {
            Start-Process notepad.exe -ArgumentList "`"$logFile`""
        } else {
            [System.Windows.MessageBox]::Show("Log file for today does not exist yet.", "TunnelKeeper", "OK", "Information")
        }
    })

    $BtnOpenLogFolder.Add_Click({
        $logDir = Join-Path $env:USERPROFILE "TunnelKeeper_Logs"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Start-Process explorer.exe -ArgumentList "`"$logDir`""
    })

    $BtnMinimizeTray.Add_Click({
        $Window.Hide()
        if ($NotifyIcon) {
            Show-TrayNotification -NotifyIcon $NotifyIcon -Title "TunnelKeeper" -Message "Running in background. Double-click icon to reopen."
        }
    })

    # ------------------------------------------------------------
    # SERVICE STATE & CONTROL
    # ------------------------------------------------------------
    function Get-ServiceState {
        $schedTask = Get-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
        $taskRunning = ($schedTask -and $schedTask.State -eq "Running")

        $mutexLocked = Get-GatewayMutexState
        $localPortNum = 0
        [int]::TryParse($TxtLocalPort.Text.Trim(), [ref]$localPortNum) | Out-Null
        $sshProcs = Get-RunningTunnels -Port $localPortNum

        $gwProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "powershell*.exe" -and $_.CommandLine -match "minecraft-tunnel-autostart\.ps1"
        }

        return ($taskRunning -or $mutexLocked -or (@($sshProcs).Count -gt 0) -or (@($gwProcs).Count -gt 0))
    }

    $startService = {
        $domain = $TxtRootDomain.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($domain) -or $domain -in @("yourdomain.com", "example.com")) {
            [System.Windows.MessageBox]::Show("Please enter your own registered domain name in the Settings tab before starting the tunnel gateway.", "Domain Configuration Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            & $setActiveTab "Settings"
            return
        }

        $p = if ($RadioCloudflare.IsChecked) { "Cloudflare" } else { "Hostinger" }
        $hToken = if ($TxtHostingerTokenVisible.Visibility -eq "Visible") { $TxtHostingerTokenVisible.Text.Trim() } else { $TxtHostingerToken.Password.Trim() }
        $cToken = if ($TxtCloudflareTokenVisible.Visibility -eq "Visible") { $TxtCloudflareTokenVisible.Text.Trim() } else { $TxtCloudflareToken.Password.Trim() }

        if ($p -eq "Hostinger" -and [string]::IsNullOrWhiteSpace($hToken)) {
            [System.Windows.MessageBox]::Show("Please enter your Hostinger API Token in Settings before starting.", "API Token Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            & $setActiveTab "Settings"
            return
        }
        if ($p -eq "Cloudflare" -and [string]::IsNullOrWhiteSpace($cToken)) {
            [System.Windows.MessageBox]::Show("Please enter your Cloudflare API Token in Settings before starting.", "API Token Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            & $setActiveTab "Settings"
            return
        }

        $BtnToggleService.IsEnabled = $false
        $BtnToggleService.Content   = "Starting..."
        $BtnToggleService.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706")

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName         = "powershell.exe"
        $psi.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CoreScriptPath`" -Force"
        $psi.WorkingDirectory = Split-Path -Parent $CoreScriptPath
        $psi.CreateNoWindow   = $true
        $psi.UseShellExecute  = $false
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }

    $stopService = {
        $BtnToggleService.IsEnabled = $false
        $BtnToggleService.Content   = "Stopping..."
        $BtnToggleService.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706")

        Stop-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue

        $localPortText = $TxtLocalPort.Text.Trim()
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io" -or ($localPortText -and $_.CommandLine -match $localPortText))
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "powershell*.exe" -and $_.CommandLine -match "minecraft-tunnel-autostart\.ps1"
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }

    $BtnToggleService.Add_Click({
        if (Get-ServiceState) {
            & $stopService
        } else {
            & $startService
        }
    })

    $BtnRestartService.Add_Click({
        & $stopService
        Start-Sleep -Seconds 2
        & $startService
    })

    # ------------------------------------------------------------
    # LIVE REFRESH TIMER
    # ------------------------------------------------------------
    $lastLogFileContent = ""
    $lastPortCheck = [DateTime]::MinValue
    $lastDnsCheck  = [DateTime]::MinValue

    $refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $refreshTimer.Interval = [TimeSpan]::FromSeconds(1)

    $refreshTimer.Add_Tick({
        $isRunning = Get-ServiceState

        if ($isRunning) {
            $BadgeStatus.Background    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
            $TxtBadgeStatus.Text       = "ONLINE"
            $TxtBadgeStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
            $BtnToggleService.Content  = "Stop Tunnel Gateway"
            $BtnToggleService.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
            $BtnToggleService.IsEnabled  = $true
        } else {
            $BadgeStatus.Background    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#450A0A")
            $TxtBadgeStatus.Text       = "STOPPED"
            $TxtBadgeStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
            $BtnToggleService.Content  = "Start Tunnel Gateway"
            $BtnToggleService.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
            $BtnToggleService.IsEnabled  = $true
        }

        $currProv = if ($RadioCloudflare.IsChecked) { "Cloudflare" } else { "Hostinger" }
        $TxtProviderLabel.Text = "Provider: $currProv"

        # Check local Minecraft server port (every 5 seconds)
        if (((Get-Date) - $lastPortCheck).TotalSeconds -ge 5) {
            $lastPortCheck = Get-Date
            $portNum = 25565
            [int]::TryParse($TxtLocalPort.Text, [ref]$portNum) | Out-Null
            $isUp = Test-LocalServer -Port $portNum
            if ($isUp) {
                $TxtLocalServerLabel.Text = "Minecraft: Online (Port $portNum)"
                $TxtLocalServerLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
            } else {
                $TxtLocalServerLabel.Text = "Minecraft: Idle (Port $portNum)"
                $TxtLocalServerLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            }
        }

        # Query public SRV record (every 15 seconds)
        if (((Get-Date) - $lastDnsCheck).TotalSeconds -ge 15) {
            $lastDnsCheck = Get-Date
            try {
                $dom = $TxtRootDomain.Text.Trim()
                if (-not [string]::IsNullOrWhiteSpace($dom) -and $dom -notin @("yourdomain.com", "example.com")) {
                    $fullSrv = "$($TxtSrvRecordName.Text).$dom"
                    $recs = Resolve-DnsName -Name $fullSrv -Type SRV -ErrorAction SilentlyContinue
                    if ($recs -and $recs.Count -gt 0) {
                        $tgt = ("" + $recs[0].Target).TrimEnd('.')
                        $prt = $recs[0].Port
                        $TxtLiveEndpoint.Text = "SRV: ${tgt}:${prt}"
                        $TxtLiveEndpoint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                    } else {
                        $TxtLiveEndpoint.Text = "SRV: Record propagating..."
                        $TxtLiveEndpoint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
                    }
                } else {
                    $TxtLiveEndpoint.Text = "SRV: Setup domain in Settings"
                    $TxtLiveEndpoint.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
                }
            } catch {}
        }

        # Read latest log file
        $logPath = Get-CurrentLogFile
        $TxtLogFileSummary.Text = Split-Path -Leaf $logPath
        $TxtFullLogPath.Text    = $logPath

        if (Test-Path $logPath) {
            $fs = $null
            $sr = $null
            try {
                $fs = [System.IO.FileStream]::new($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                $logContent = $sr.ReadToEnd()

                if ($logContent -ne $lastLogFileContent) {
                    $lastLogFileContent = $logContent

                    $lines = $logContent -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $tailCount = [math]::Min(12, $lines.Count)
                    if ($tailCount -gt 0) {
                        $recent = ($lines[($lines.Count - $tailCount)..($lines.Count - 1)]) -join "`r`n"
                        $TxtDashboardLogs.Text = $recent
                        $TxtDashboardLogs.ScrollToEnd()
                    }

                    $TxtFullLogs.Text = $logContent
                    if ($ChkAutoScroll.IsChecked) {
                        $TxtFullLogs.ScrollToEnd()
                    }

                    $swapMatch = [regex]::Matches($logContent, 'Swap #(\d+)')
                    if ($swapMatch.Count -gt 0) {
                        $TxtCycleCount.Text = "Swaps: $($swapMatch[$swapMatch.Count - 1].Groups[1].Value) completed"
                    }
                    $uptimeMatch = [regex]::Matches($logContent, 'Uptime: ([0-9dhms ]+)')
                    if ($uptimeMatch.Count -gt 0) {
                        $TxtUptime.Text = "Uptime: " + $uptimeMatch[$uptimeMatch.Count - 1].Groups[1].Value.Trim()
                    }
                }
            } catch {
            } finally {
                if ($sr) { $sr.Dispose() }
                if ($fs) { $fs.Dispose() }
            }
        }
    })

    $refreshTimer.Start()

    return @{
        RefreshTimer  = $refreshTimer
        StartService  = $startService
        StopService   = $stopService
    }
}
