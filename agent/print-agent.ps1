
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing config.json. Copy config.example.json to config.json and edit it."
}

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json

$siteUrl = ([string]$config.siteUrl).TrimEnd('/')
$pollSeconds = [Math]::Max(5, [int]$config.pollSeconds)

if ($siteUrl -notmatch '^https://') {
    throw "siteUrl must use HTTPS."
}

if ([string]::IsNullOrWhiteSpace($config.agentToken)) {
    throw "agentToken is missing."
}

if ([string]::IsNullOrWhiteSpace($config.printerName)) {
    throw "printerName is missing."
}

$headers = @{
    Authorization = "Bearer $($config.agentToken)"
}

$temp = Join-Path $env:TEMP 'networking-remote-print'
New-Item -ItemType Directory -Force -Path $temp | Out-Null

Write-Host "Remote print agent running. Printer: $($config.printerName). Press Ctrl+C to stop."
Write-Host "Polling every $pollSeconds seconds."

while ($true) {
    $job = $null
    $file = $null

    try {
        $jobResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "$siteUrl/api/agent/next" `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body '{}'

        if ($null -eq $jobResponse.job) {
            Start-Sleep -Seconds $pollSeconds
            continue
        }

        $job = $jobResponse.job

        $ext = if ($job.mime_type -eq 'application/pdf') {
            '.pdf'
        } elseif ($job.mime_type -eq 'image/jpeg') {
            '.jpg'
        } else {
            throw "Unsupported MIME type: $($job.mime_type)"
        }

        $file = Join-Path $temp ("job-" + $job.id + $ext)

        Invoke-WebRequest -Uri $job.download_url -OutFile $file

        if (-not (Test-Path -LiteralPath $file) -or
            (Get-Item -LiteralPath $file).Length -lt 1) {
            throw "Downloaded print file is missing or empty."
        }

        if ($ext -eq '.pdf') {
            if (-not (Test-Path -LiteralPath $config.sumatraPath)) {
                throw "SumatraPDF not found: $($config.sumatraPath)"
            }

            $copies = [int]$job.copies

            if ($copies -lt 1 -or $copies -gt 5) {
                throw "Invalid copy count."
            }

            $settings = "copies=$copies,fit,paper=$($job.paper_size.ToLower()),$(if ($job.color_mode -eq 'bw') { 'monochrome' } else { 'color' })"

            if ($null -ne $job.page_start -and $null -ne $job.page_end) {
                $settings += ",$($job.page_start)-$($job.page_end)"
            }

            & $config.sumatraPath -silent -print-to $config.printerName -print-settings $settings $file

            if ($LASTEXITCODE -ne 0) {
                throw "SumatraPDF exited with code $LASTEXITCODE."
            }
        }
        else {
            if ($null -ne $job.page_start -or $null -ne $job.page_end) {
                throw "Page ranges are only supported for PDF files."
            }

            $helper = Join-Path $PSScriptRoot 'print-jpg.ps1'

            if (-not (Test-Path -LiteralPath $helper)) {
                throw "print-jpg.ps1 helper is missing."
            }

            & $helper `
                -ImagePath $file `
                -PrinterName $config.printerName `
                -Copies ([int]$job.copies) `
                -PaperSize $job.paper_size `
                -ColorMode $job.color_mode
        }

        $resultBody = @{
            id = $job.id
            status = 'completed'
            message = 'Submitted to the Windows print queue. Check the printer for physical output.'
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Method Post `
            -Uri "$siteUrl/api/agent/result" `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body $resultBody | Out-Null

        Write-Host "Job $($job.id) submitted to printer queue."

        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Warning $errorMessage

        if ($null -ne $job -and $job.id) {
            try {
                $failureBody = @{
                    id = $job.id
                    status = 'failed'
                    message = $errorMessage
                } | ConvertTo-Json

                Invoke-RestMethod `
                    -Method Post `
                    -Uri "$siteUrl/api/agent/result" `
                    -Headers $headers `
                    -ContentType 'application/json' `
                    -Body $failureBody | Out-Null
            }
            catch {
                Write-Warning "Could not report job failure: $($_.Exception.Message)"
            }
        }

        if ($file) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }

        Start-Sleep -Seconds 5
    }
}
