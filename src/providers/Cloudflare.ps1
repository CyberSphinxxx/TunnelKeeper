<#
====================================================================
 TunnelKeeper - Cloudflare DNS Provider Module
 Discovers Zone ID and manages SRV records via the Cloudflare API v4
====================================================================
#>

$script:CachedCloudflareZoneId = $null

function Get-CloudflareZoneId {
    param(
        [Parameter(Mandatory=$true)][string]$RootDomain,
        [Parameter(Mandatory=$true)][string]$CloudflareApiToken,
        [string]$ExplicitZoneId
    )

    if (-not [string]::IsNullOrEmpty($ExplicitZoneId)) {
        return $ExplicitZoneId
    }
    if (-not [string]::IsNullOrEmpty($script:CachedCloudflareZoneId)) {
        return $script:CachedCloudflareZoneId
    }

    $headers = @{
        "Authorization" = "Bearer $CloudflareApiToken"
        "Content-Type"  = "application/json"
    }

    try {
        $uri = "https://api.cloudflare.com/client/v4/zones?name=$RootDomain"
        $resp = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
        if ($resp.success -and $resp.result -and $resp.result.Count -gt 0) {
            $script:CachedCloudflareZoneId = $resp.result[0].id
            return $script:CachedCloudflareZoneId
        } else {
            Write-Log "[Cloudflare] Zone '$RootDomain' not found in account." "Red"
        }
    } catch {
        Write-Log "[Cloudflare] Error retrieving Zone ID for '$RootDomain': $_" "Red"
    }
    return $null
}

function Update-CloudflareSRV {
    param(
        [Parameter(Mandatory=$true)][string]$RootDomain,
        [Parameter(Mandatory=$true)][string]$SrvRecordName,
        [Parameter(Mandatory=$true)][string]$TargetHost,
        [Parameter(Mandatory=$true)][int]$TargetPort,
        [int]$Priority = 0,
        [int]$Weight = 5,
        [int]$TTL = 60,
        [Parameter(Mandatory=$true)][string]$CloudflareApiToken,
        [string]$CloudflareZoneId
    )

    $zoneId = Get-CloudflareZoneId -RootDomain $RootDomain -CloudflareApiToken $CloudflareApiToken -ExplicitZoneId $CloudflareZoneId
    if (-not $zoneId) {
        Write-Log "[Cloudflare] Cannot update DNS without a valid Zone ID." "Red"
        return $false
    }

    $headers = @{
        "Authorization" = "Bearer $CloudflareApiToken"
        "Content-Type"  = "application/json"
    }

    # Parse service, proto, and name from $SrvRecordName (e.g. _minecraft._tcp.play or _minecraft._tcp)
    $service = "_minecraft"
    $proto   = "_tcp"
    $name    = "@"

    if ($SrvRecordName -match '^_([a-zA-Z0-9]+)\._([a-zA-Z0-9]+)\.?(.*)$') {
        $service = "_$($matches[1])"
        $proto   = "_$($matches[2])"
        $name    = if ($matches[3]) { $matches[3] } else { "@" }
    }

    $fullRecordName = "$SrvRecordName.$RootDomain"

    $bodyObj = @{
        type = "SRV"
        name = $fullRecordName
        ttl  = $TTL
        data = @{
            service  = $service
            proto    = $proto
            name     = $name
            priority = $Priority
            weight   = $Weight
            port     = $TargetPort
            target   = $TargetHost.TrimEnd('.')
        }
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5

    # Check if record already exists
    $existingRecordId = $null
    try {
        $searchUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=SRV&name=$fullRecordName"
        $searchResp = Invoke-RestMethod -Uri $searchUri -Method GET -Headers $headers
        if ($searchResp.success -and $searchResp.result -and $searchResp.result.Count -gt 0) {
            $existingRecordId = $searchResp.result[0].id
        }
    } catch {
        Write-Log "[Cloudflare] Querying existing SRV record returned error: $_" "Yellow"
    }

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            if ($existingRecordId) {
                # Update existing record
                $putUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$existingRecordId"
                $resp = Invoke-RestMethod -Uri $putUri -Method PUT -Headers $headers -Body $bodyJson
            } else {
                # Create new record
                $postUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
                $resp = Invoke-RestMethod -Uri $postUri -Method POST -Headers $headers -Body $bodyJson
                if ($resp.success -and $resp.result) {
                    $existingRecordId = $resp.result.id
                }
            }

            if ($resp.success) {
                Write-Log "[Cloudflare] Updated $fullRecordName -> ${TargetHost}:${TargetPort}" "Green"
                return $true
            } else {
                Write-Log "[Cloudflare] API error: $($resp.errors | ConvertTo-Json -Compress)" "Yellow"
            }
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Log "[Cloudflare] Attempt $attempt/$maxRetries returned error. Retrying in 5s..." "Yellow"
                Start-Sleep -Seconds 5
            } else {
                Write-Log "[Cloudflare] All $maxRetries attempts failed: $_" "Red"
            }
        }
    }
    return $false
}
