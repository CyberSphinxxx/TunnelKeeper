<#
====================================================================
 TunnelKeeper - GUI System Tray Module
 Manages Windows WinForms NotifyIcon, tray menu, and balloon tips
====================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Initialize-SystemTray {
    param(
        [Parameter(Mandatory=$true)]$Window,
        [string]$IconFilePath,
        [scriptblock]$OnStartTunnel,
        [scriptblock]$OnStopTunnel,
        [scriptblock]$OnExit
    )

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Text = "TunnelKeeper - Minecraft Gateway"

    if ($IconFilePath -and (Test-Path $IconFilePath)) {
        try {
            $notifyIcon.Icon = New-Object System.Drawing.Icon($IconFilePath)
        } catch {
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
        }
    } else {
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    }

    $notifyIcon.Visible = $true

    # Context Menu
    $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $menuItemDashboard = $contextMenu.Items.Add("Open Dashboard")
    $menuItemDashboard.Font = New-Object System.Drawing.Font($menuItemDashboard.Font, [System.Drawing.FontStyle]::Bold)
    $menuItemDashboard.Add_Click({
        $Window.Dispatcher.Invoke([Action]{
            $Window.Show()
            $Window.WindowState = [System.Windows.WindowState]::Normal
            $Window.Activate()
        })
    })

    $null = $contextMenu.Items.Add("-")

    $menuItemStart = $contextMenu.Items.Add("Start Tunnel")
    $menuItemStart.Add_Click({
        if ($OnStartTunnel) { & $OnStartTunnel }
    })

    $menuItemStop = $contextMenu.Items.Add("Stop Tunnel")
    $menuItemStop.Add_Click({
        if ($OnStopTunnel) { & $OnStopTunnel }
    })

    $null = $contextMenu.Items.Add("-")

    $menuItemExit = $contextMenu.Items.Add("Exit TunnelKeeper")
    $menuItemExit.Add_Click({
        if ($OnExit) {
            & $OnExit
        } else {
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
            [System.Windows.Application]::Current.Shutdown()
        }
    })

    $notifyIcon.ContextMenuStrip = $contextMenu

    # Double click opens dashboard
    $notifyIcon.Add_DoubleClick({
        $Window.Dispatcher.Invoke([Action]{
            $Window.Show()
            $Window.WindowState = [System.Windows.WindowState]::Normal
            $Window.Activate()
        })
    })

    return $notifyIcon
}

function Show-TrayNotification {
    param(
        [Parameter(Mandatory=$true)]$NotifyIcon,
        [string]$Title = "TunnelKeeper",
        [string]$Message = "",
        [string]$Type = "Info",
        [int]$TimeoutMs = 2000
    )

    if (-not $NotifyIcon) { return }

    $iconType = switch ($Type.ToLower()) {
        "warning" { [System.Windows.Forms.ToolTipIcon]::Warning }
        "error"   { [System.Windows.Forms.ToolTipIcon]::Error }
        default   { [System.Windows.Forms.ToolTipIcon]::Info }
    }

    $NotifyIcon.ShowBalloonTip($TimeoutMs, $Title, $Message, $iconType)
}
