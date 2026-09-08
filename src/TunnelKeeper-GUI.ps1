<#
====================================================================
 TunnelKeeper - Modern Native WPF Dark-Mode Dashboard
 Application entry and presentation bootstrap orchestrator
====================================================================
#>

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
$app = [System.Windows.Application]::Current
if (-not $app) { $app = New-Object System.Windows.Application }
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

# ------------------------------------------------------------
# PATHS & MODULE DISCOVERY
# ------------------------------------------------------------
$ScriptRoot  = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }
if (-not $ScriptRoot) { $ScriptRoot = (Get-Location).Path }

$RepoRoot = if (Test-Path (Join-Path $ScriptRoot "..\.env.example")) {
    (Resolve-Path (Join-Path $ScriptRoot "..")).Path
} elseif (Test-Path (Join-Path $ScriptRoot "..\.env")) {
    (Resolve-Path (Join-Path $ScriptRoot "..")).Path
} else {
    $ScriptRoot
}

$CoreScriptPath = Join-Path $ScriptRoot "minecraft-tunnel-autostart.ps1"
if (-not (Test-Path $CoreScriptPath)) {
    $CoreScriptPath = Join-Path $RepoRoot "src\minecraft-tunnel-autostart.ps1"
}

$EnvFilePath = Join-Path $RepoRoot ".env"
if (-not (Test-Path $EnvFilePath) -and (Test-Path (Join-Path $ScriptRoot ".env"))) {
    $EnvFilePath = Join-Path $ScriptRoot ".env"
}

$IconFilePath = Join-Path $RepoRoot "assets\TunnelKeeper.ico"
if (-not (Test-Path $IconFilePath)) {
    $IconFilePath = Join-Path $ScriptRoot "assets\TunnelKeeper.ico"
}
if (-not (Test-Path $IconFilePath)) {
    $IconFilePath = Join-Path $RepoRoot "TunnelKeeper.ico"
}

# ------------------------------------------------------------
# LOAD MODULAR COMPONENTS
# ------------------------------------------------------------
. (Join-Path $ScriptRoot "core\Config.ps1")
. (Join-Path $ScriptRoot "core\Logger.ps1")
. (Join-Path $ScriptRoot "core\Network.ps1")
. (Join-Path $ScriptRoot "gui\SystemTray.ps1")
. (Join-Path $ScriptRoot "gui\Dashboard.ps1")

# ------------------------------------------------------------
# LOAD XAML & WINDOW
# ------------------------------------------------------------
$xamlPath = Join-Path $ScriptRoot "gui\MainWindow.xaml"
$xmlReader = [System.Xml.XmlReader]::Create($xamlPath)
try {
    $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
} finally {
    $xmlReader.Close()
}

if ($IconFilePath -and (Test-Path $IconFilePath)) {
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($IconFilePath))
    } catch {}
}

# ------------------------------------------------------------
# INITIALIZE CONTROLLERS
# ------------------------------------------------------------
$script:IsExplicitExit = $false
$controllerRef = $null
$notifyIconRef = $null

$onExit = {
    $script:IsExplicitExit = $true
    if ($controllerRef -and $controllerRef.RefreshTimer) {
        $controllerRef.RefreshTimer.Stop()
    }
    if ($notifyIconRef) {
        $notifyIconRef.Visible = $false
        $notifyIconRef.Dispose()
    }
    $window.Close()
    $app.Shutdown()
}

$notifyIconRef = Initialize-SystemTray -Window $window -IconFilePath $IconFilePath `
    -OnStartTunnel { if ($controllerRef) { & $controllerRef.StartService } } `
    -OnStopTunnel  { if ($controllerRef) { & $controllerRef.StopService } } `
    -OnExit        $onExit

$controllerRef = Initialize-DashboardController -Window $window `
    -EnvFilePath $EnvFilePath `
    -CoreScriptPath $CoreScriptPath `
    -NotifyIcon $notifyIconRef

# ------------------------------------------------------------
# WINDOW CLOSE / MINIMIZE TO TRAY
# ------------------------------------------------------------
$window.Add_Closing({
    param($sender, $e)
    if (-not $script:IsExplicitExit) {
        $e.Cancel = $true
        $window.Hide()
        Show-TrayNotification -NotifyIcon $notifyIconRef -Title "TunnelKeeper" -Message "Minimized to tray. Double-click icon to reopen."
    }
})

# ------------------------------------------------------------
# RUN APPLICATION
# ------------------------------------------------------------
$window.Show()
$app.Run() | Out-Null
