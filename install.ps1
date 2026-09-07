<#
============================================================
 TunnelKeeper - 1-Line PowerShell Web Installer
============================================================
 Usage:
   irm https://raw.githubusercontent.com/CyberSphinxxx/TunnelKeeper/main/install.ps1 | iex
   or locally:
   .\install.ps1 [-Uninstall]
============================================================
#>

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$NoLaunch
)

$RepoBaseUrl = "https://raw.githubusercontent.com/CyberSphinxxx/TunnelKeeper/main"
$InstallDir  = Join-Path $env:LOCALAPPDATA "TunnelKeeper"
$DesktopDir  = [System.Environment]::GetFolderPath('Desktop')
$StartMenuDir = Join-Path ([System.Environment]::GetFolderPath('StartMenu')) "Programs"

$DesktopShortcut   = Join-Path $DesktopDir "TunnelKeeper.lnk"
$StartMenuShortcut = Join-Path $StartMenuDir "TunnelKeeper.lnk"

# ------------------------------------------------------------
# UNINSTALL HANDLER
# ------------------------------------------------------------
if ($Uninstall) {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "   TunnelKeeper - Uninstaller                          " -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[1/3] Stopping any running background tunnels..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName "Minecraft Tunnel Keeper" -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "ssh.exe" -and ($_.CommandLine -match "a\.pinggy\.io")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "powershell*.exe" -and ($_.CommandLine -match "TunnelKeeper-GUI\.ps1" -or $_.CommandLine -match "minecraft-tunnel-autostart\.ps1")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Write-Host "[2/3] Removing shortcuts..." -ForegroundColor Yellow
    if (Test-Path $DesktopShortcut) { Remove-Item $DesktopShortcut -Force -ErrorAction SilentlyContinue }
    if (Test-Path $StartMenuShortcut) { Remove-Item $StartMenuShortcut -Force -ErrorAction SilentlyContinue }

    Write-Host "[3/3] Removing installation files ($InstallDir)..." -ForegroundColor Yellow
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "TunnelKeeper has been cleanly uninstalled from your PC." -ForegroundColor Green
    Write-Host ""
    return
}

# ------------------------------------------------------------
# INSTALLATION PROCESS
# ------------------------------------------------------------
Write-Host ""
Write-Host "  =======================================================" -ForegroundColor Cyan
Write-Host "   _______ _    _ _   _ _   _ ______ _                  " -ForegroundColor Cyan
Write-Host "  |__   __| |  | | \ | | \ | |  ____| |                 " -ForegroundColor Cyan
Write-Host "     | |  | |  | |  \| |  \| | |__  | |                 " -ForegroundColor Cyan
Write-Host "     | |  | |  | | . ` | . ` |  __| | |                 " -ForegroundColor Cyan
Write-Host "     | |  | |__| | |\  | |\  | |____| |____             " -ForegroundColor Cyan
Write-Host "     |_|   \____/|_| \_|_| \_|______|______|            " -ForegroundColor Cyan
Write-Host "          TunnelKeeper Setup & Installer                " -ForegroundColor Cyan
Write-Host "  =======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. System Verification
Write-Host "[1/5] Checking system prerequisites..." -ForegroundColor Yellow

# OpenSSH client check
$hasSsh = $false
try {
    $null = & ssh -V 2>&1
    $hasSsh = $true
} catch {
    $hasSsh = $false
}

if (-not $hasSsh) {
    Write-Host "      Notice: OpenSSH client not detected." -ForegroundColor Yellow
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "      Installing Windows OpenSSH client..." -ForegroundColor Cyan
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
    } else {
        Write-Host "      Please ensure Windows OpenSSH Client is installed via Optional Features." -ForegroundColor Gray
    }
} else {
    Write-Host "      OpenSSH Client: OK" -ForegroundColor Green
}

# 2. Prepare Install Directory
Write-Host "[2/5] Preparing installation directory..." -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Write-Host "      Target directory: $InstallDir" -ForegroundColor DarkGray

# 3. Download / Copy Files
Write-Host "[3/5] Installing application files..." -ForegroundColor Yellow

$files = @(
    "TunnelKeeper.exe",
    "src/main.ps1",
    "src/TunnelKeeper-GUI.ps1",
    "src/minecraft-tunnel-autostart.ps1",
    "scripts/TunnelKeeper.bat",
    "scripts/TunnelKeeper.vbs",
    "assets/TunnelKeeper.ico",
    ".env.example"
)

# If running from local repository, copy locally. Otherwise, download from GitHub.
$isLocalRepo = (Test-Path (Join-Path $PSScriptRoot "src\main.ps1")) -or (Test-Path (Join-Path $PSScriptRoot "TunnelKeeper-GUI.ps1"))

foreach ($file in $files) {
    $dest = Join-Path $InstallDir ($file -replace '/', '\')
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    if ($isLocalRepo) {
        $source = Join-Path $PSScriptRoot ($file -replace '/', '\')
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination $dest -Force
            Write-Host "      [Copy] $file" -ForegroundColor DarkGray
        }
    } else {
        $downloadUrl = "$RepoBaseUrl/$file"
        try {
            Invoke-RestMethod -Uri $downloadUrl -OutFile $dest
            Write-Host "      [Download] $file" -ForegroundColor DarkGray
        } catch {
            if ($file -ne "TunnelKeeper.exe") {
                Write-Host "      [Warning] Could not download $($file): $_" -ForegroundColor Yellow
            }
        }
    }
}

# If TunnelKeeper.exe was not downloaded or copied, compile it locally using built-in csc.exe
$targetExe = Join-Path $InstallDir "TunnelKeeper.exe"
if (-not (Test-Path $targetExe)) {
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
    if (Test-Path $csc) {
        Write-Host "      [Compile] Compiling native TunnelKeeper.exe via built-in csc.exe..." -ForegroundColor DarkGray
        $srcPath = Join-Path $env:TEMP "TunnelKeeperLauncher.cs"
        $code = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace TunnelKeeperLauncher {
    static class Program {
        [STAThread]
        static void Main(string[] args) {
            try {
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string script = Path.Combine(exeDir, "src", "main.ps1");
                if (!File.Exists(script)) { script = Path.Combine(exeDir, "main.ps1"); }
                if (!File.Exists(script)) { script = Path.Combine(exeDir, "src", "TunnelKeeper-GUI.ps1"); }
                if (!File.Exists(script)) { script = Path.Combine(exeDir, "TunnelKeeper-GUI.ps1"); }
                if (!File.Exists(script)) {
                    MessageBox.Show("Could not locate 'src/main.ps1' or 'TunnelKeeper-GUI.ps1' in:\n" + exeDir, "TunnelKeeper Launcher Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                string argLine = "-NoProfile -Sta -ExecutionPolicy Bypass -File \"" + script + "\"";
                if (args != null && args.Length > 0) { argLine += " " + string.Join(" ", args); }
                ProcessStartInfo psi = new ProcessStartInfo {
                    FileName = "powershell.exe",
                    Arguments = argLine,
                    WorkingDirectory = exeDir,
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi);
            } catch (Exception ex) {
                MessageBox.Show(ex.Message, "TunnelKeeper Launcher Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
"@
        Set-Content -Path $srcPath -Value $code -Encoding UTF8
        $iconTarget = Join-Path $InstallDir "assets\TunnelKeeper.ico"
        if (-not (Test-Path $iconTarget)) {
            $iconTarget = Join-Path $InstallDir "TunnelKeeper.ico"
        }
        $cArgs = @("/target:winexe", "/optimize+", "/out:`"$targetExe`"", "/reference:System.Windows.Forms.dll", "/reference:System.dll")
        if (Test-Path $iconTarget) { $cArgs += "/win32icon:`"$iconTarget`"" }
        $cArgs += "`"$srcPath`""
        Start-Process -FilePath $csc -ArgumentList ($cArgs -join " ") -NoNewWindow -Wait | Out-Null
        Remove-Item -Path $srcPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $targetExe) {
            Write-Host "      [Compile] Compiled native TunnelKeeper.exe successfully!" -ForegroundColor Green
        }
    }
}

# Ensure .env exists if not already present
$targetEnv = Join-Path $InstallDir ".env"
$sourceEnv = Join-Path $InstallDir ".env.example"
if ((-not (Test-Path $targetEnv)) -and (Test-Path $sourceEnv)) {
    Copy-Item -Path $sourceEnv -Destination $targetEnv
    Write-Host "      Created initial .env config template." -ForegroundColor DarkGray
}

# 4. Create Desktop and Start Menu Shortcuts
Write-Host "[4/5] Creating Windows shortcuts..." -ForegroundColor Yellow

$wshShell = New-Object -ComObject WScript.Shell

$exePath = Join-Path $InstallDir "TunnelKeeper.exe"
$vbsPath = Join-Path $InstallDir "scripts\TunnelKeeper.vbs"
if (-not (Test-Path $vbsPath)) {
    $vbsPath = Join-Path $InstallDir "TunnelKeeper.vbs"
}
$icoPath = Join-Path $InstallDir "assets\TunnelKeeper.ico"
if (-not (Test-Path $icoPath)) {
    $icoPath = Join-Path $InstallDir "TunnelKeeper.ico"
}

$targetApp = if (Test-Path $exePath) { $exePath } else { "$env:SystemRoot\System32\wscript.exe" }
$targetArgs = if (Test-Path $exePath) { "" } else { "`"$vbsPath`"" }

try {
    $shortcut = $wshShell.CreateShortcut($DesktopShortcut)
    $shortcut.TargetPath = $targetApp
    $shortcut.Arguments  = $targetArgs
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.IconLocation = "$icoPath,0"
    $shortcut.Description = "TunnelKeeper - Minecraft Dynamic Tunnel Gateway"
    $shortcut.Save()
    Write-Host "      Created Desktop Shortcut: TunnelKeeper" -ForegroundColor Green
} catch {
    Write-Host "      Could not create desktop shortcut: $_" -ForegroundColor Yellow
}

# Start Menu shortcut
try {
    if (-not (Test-Path $StartMenuDir)) { New-Item -ItemType Directory -Path $StartMenuDir -Force | Out-Null }
    $shortcut2 = $wshShell.CreateShortcut($StartMenuShortcut)
    $shortcut2.TargetPath = $targetApp
    $shortcut2.Arguments  = $targetArgs
    $shortcut2.WorkingDirectory = $InstallDir
    $shortcut2.IconLocation = "$icoPath,0"
    $shortcut2.Description = "TunnelKeeper - Minecraft Dynamic Tunnel Gateway"
    $shortcut2.Save()
    Write-Host "      Created Start Menu Shortcut: TunnelKeeper" -ForegroundColor Green
} catch {}

# 5. Completion & Launch
Write-Host "[5/5] Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  =======================================================" -ForegroundColor Cyan
Write-Host "   TunnelKeeper was installed successfully!              " -ForegroundColor Green
Write-Host "  =======================================================" -ForegroundColor Cyan
Write-Host "   Directory    : $InstallDir                            " -ForegroundColor White
Write-Host "   Desktop Icon : Created                                " -ForegroundColor White
Write-Host "   Start Menu   : Registered                             " -ForegroundColor White
Write-Host ""

if (-not $NoLaunch) {
    Write-Host "Launching TunnelKeeper Dashboard..." -ForegroundColor Cyan
    if (Test-Path $exePath) {
        Start-Process $exePath
    } else {
        Start-Process "$env:SystemRoot\System32\wscript.exe" -ArgumentList "`"$vbsPath`""
    }
}
