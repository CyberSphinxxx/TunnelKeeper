<#
====================================================================
 TunnelKeeper - Core Logging Module
 Timestamped console & file output with automatic log rotation
====================================================================
#>

$script:LogDir = Join-Path $env:USERPROFILE "TunnelKeeper_Logs"
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

function Get-CurrentLogFile {
    param([string]$LogDir = $script:LogDir)
    return Join-Path $LogDir ("gateway_$(Get-Date -Format 'yyyy-MM-dd').log")
}

$script:MaskTokens = [System.Collections.Generic.List[string]]::new()

function Register-MaskToken {
    param([string]$Token)
    if (-not [string]::IsNullOrWhiteSpace($Token) -and $Token.Length -ge 6) {
        if (-not $script:MaskTokens.Contains($Token)) {
            $script:MaskTokens.Add($Token)
        }
    }
}

function Sanitize-LogMessage {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    foreach ($token in $script:MaskTokens) {
        if (-not [string]::IsNullOrEmpty($token)) {
            $Text = $Text -replace [regex]::Escape($token), "****************"
        }
    }
    return $Text
}

$script:LogFile = Get-CurrentLogFile

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoConsole
    )

    $Message   = Sanitize-LogMessage $Message
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] $Message"

    if (-not $NoConsole) {
        switch ($Color.ToLower()) {
            "green"    { Write-Host $logLine -ForegroundColor Green }
            "red"      { Write-Host $logLine -ForegroundColor Red }
            "yellow"   { Write-Host $logLine -ForegroundColor Yellow }
            "cyan"     { Write-Host $logLine -ForegroundColor Cyan }
            "darkgray" { Write-Host $logLine -ForegroundColor DarkGray }
            default    { Write-Host $logLine -ForegroundColor White }
        }
    }

    try {
        # Update target file if date rolled over
        $script:LogFile = Get-CurrentLogFile
        $logLine | Out-File -FilePath $script:LogFile -Append -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}
}

function Rotate-Logs {
    param(
        [int]$RetentionDays = 14,
        [string]$LogDir = $script:LogDir
    )

    if (-not (Test-Path $LogDir)) { return }
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    
    Get-ChildItem -Path $LogDir -Filter "gateway_*.log" -File -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "[MAINT] Cleaned up expired log file: $($_.Name)" "DarkGray"
        } catch {}
    }
}
