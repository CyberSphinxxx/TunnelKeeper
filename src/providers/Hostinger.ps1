<#
====================================================================
 TunnelKeeper - Hostinger DNS Provider Module
 Updates SRV records via the Hostinger Developers REST API
====================================================================
#>

function Remove-OldHostingerSrvRecords {
    param(
        [Parameter(Mandatory=$true)][string]$RootDomain,
        [Parameter(Mandatory=$true)][string]$SrvRecordName,
        [Parameter(Mandatory=$true)][string]$HostingerToken
    )

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
        Write-Log "[Hostinger] Cleaned up old SRV records" "DarkGray"
        return $true
    } catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($status -eq 404) {
            Write-Log "[Hostinger] No old SRV records to clean (404)" "DarkGray"
            return $true
        } else {
            Write-Log "[Hostinger] Warning: could not clean old records: $_" "Yellow"
            return $false
        }
    }
}

function Update-HostingerSRV {
    param(
        [Parameter(Mandatory=$true)][string]$RootDomain,
        [Parameter(Mandatory=$true)][string]$SrvRecordName,
        [Parameter(Mandatory=$true)][string]$TargetHost,
        [Parameter(Mandatory=$true)][int]$TargetPort,
        [int]$Priority = 0,
        [int]$Weight = 5,
        [int]$TTL = 60,
        [Parameter(Mandatory=$true)][string]$HostingerToken
    )

    $deleteOk = Remove-OldHostingerSrvRecords -RootDomain $RootDomain -SrvRecordName $SrvRecordName -HostingerToken $HostingerToken
    if (-not $deleteOk) {
        Write-Log "[Hostinger] Delete failed - skipping PUT to avoid duplicate. Will retry." "Yellow"
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
            Write-Log "[Hostinger] Updated $SrvRecordName.$RootDomain -> ${TargetHost}:${TargetPort}" "Green"
            return $true
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Log "[Hostinger] PUT attempt $attempt/$maxRetries returned error. Retrying in 5s..." "Yellow"
                Start-Sleep -Seconds 5
            } else {
                Write-Log "[Hostinger] All $maxRetries attempts failed: $_" "Red"
            }
        }
    }
    return $false
}
