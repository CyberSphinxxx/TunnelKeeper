<#
============================================================
 TunnelKeeper - Native .EXE Compiler
 Compiles TunnelKeeper.exe with custom icon and no console
============================================================
#>

[CmdletBinding()]
param()

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$RepoRoot = if (Test-Path (Join-Path $ScriptDir "..\TunnelKeeper-GUI.ps1")) {
    (Resolve-Path (Join-Path $ScriptDir "..")).Path
} elseif (Test-Path (Join-Path $ScriptDir "TunnelKeeper-GUI.ps1")) {
    $ScriptDir
} else {
    (Resolve-Path (Join-Path $ScriptDir "..")).Path
}

$CscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $CscPath)) {
    $CscPath = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

if (-not (Test-Path $CscPath)) {
    Write-Host "Error: C# compiler (csc.exe) not found on this system." -ForegroundColor Red
    exit 1
}

$IconPath = Join-Path $RepoRoot "assets\TunnelKeeper.ico"
if (-not (Test-Path $IconPath)) {
    $IconPath = Join-Path $RepoRoot "TunnelKeeper.ico"
}
$OutputExe = Join-Path $RepoRoot "TunnelKeeper.exe"
$SourceCodePath = Join-Path $env:TEMP "TunnelKeeperLauncher.cs"

$SourceCode = @"
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
                string guiScript = Path.Combine(exeDir, "TunnelKeeper-GUI.ps1");
                
                if (!File.Exists(guiScript)) {
                    MessageBox.Show(
                        "Could not locate 'TunnelKeeper-GUI.ps1' in:\n" + exeDir,
                        "TunnelKeeper Launcher Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                string argLine = "-NoProfile -Sta -ExecutionPolicy Bypass -File \"" + guiScript + "\"";
                if (args != null && args.Length > 0) {
                    argLine += " " + string.Join(" ", args);
                }

                ProcessStartInfo psi = new ProcessStartInfo {
                    FileName = "powershell.exe",
                    Arguments = argLine,
                    WorkingDirectory = exeDir,
                    CreateNoWindow = true,
                    UseShellExecute = false
                };

                Process p = Process.Start(psi);
                if (p == null) {
                    MessageBox.Show(
                        "Failed to launch PowerShell process.",
                        "TunnelKeeper Launcher Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                }
            } catch (Exception ex) {
                MessageBox.Show(ex.Message, "TunnelKeeper Launcher Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
"@

Set-Content -Path $SourceCodePath -Value $SourceCode -Encoding UTF8

$argsList = @(
    "/target:winexe",
    "/optimize+",
    "/out:`"$OutputExe`"",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.dll"
)

if (Test-Path $IconPath) {
    $argsList += "/win32icon:`"$IconPath`""
}

$argsList += "`"$SourceCodePath`""

Write-Host "Compiling native TunnelKeeper.exe..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $CscPath -ArgumentList ($argsList -join " ") -NoNewWindow -Wait -PassThru

Remove-Item -Path $SourceCodePath -Force -ErrorAction SilentlyContinue

if ($proc.ExitCode -eq 0 -and (Test-Path $OutputExe)) {
    $sizeKb = [math]::Round(((Get-Item $OutputExe).Length / 1KB), 1)
    Write-Host "Success! Compiled: $OutputExe ($sizeKb KB)" -ForegroundColor Green
} else {
    Write-Host "Compilation failed with exit code: $($proc.ExitCode)" -ForegroundColor Red
}
