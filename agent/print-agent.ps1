param([string]$ConfigPath = "$PSScriptRoot\config.json")
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $ConfigPath)){throw "Missing config.json. Copy config.example.json to config.json and edit it."}
$config=Get-Content -Raw -LiteralPath $ConfigPath|ConvertFrom-Json
if($config.siteUrl -notmatch '^https://'){throw "siteUrl must use HTTPS."}
if([string]::IsNullOrWhiteSpace($config.agentToken)){throw "agentToken is missing."}
$headers=@{Authorization="Bearer $($config.agentToken)"}
$temp=Join-Path $env:TEMP 'networking-remote-print'
New-Item -ItemType Directory -Force -Path $temp|Out-Null
Write-Host "Remote print agent running. Printer: $($config.printerName). Press Ctrl+C to stop."
while($true){
 try{
  $jobResponse=Invoke-RestMethod -Method Post -Uri "$($config.siteUrl)/api/agent/next" -Headers $headers -ContentType 'application/json' -Body '{}'
  if($null -eq $jobResponse.job){Start-Sleep -Seconds ([Math]::Max(5,[int]$config.pollSeconds));continue}
  $job=$jobResponse.job
  $ext=if($job.mime_type -eq 'application/pdf'){'.pdf'}elseif($job.mime_type -eq 'image/jpeg'){'.jpg'}else{throw "Unsupported MIME type from server."}
  $file=Join-Path $temp ("job-"+$job.id+$ext)
  Invoke-WebRequest -Uri $job.download_url -OutFile $file
  if($ext -eq '.pdf'){
   if(-not(Test-Path -LiteralPath $config.sumatraPath)){throw "SumatraPDF executable not found at configured path."}
   $settings="$([int]$job.copies)x,fit,paper=$($job.paper_size.ToLower()),$(if($job.color_mode -eq 'bw'){'monochrome'}else{'color'})"
   if($null -ne $job.page_start -and $null -ne $job.page_end){$settings+=",$($job.page_start)-$($job.page_end)"}
   & $config.sumatraPath -silent -print-to $config.printerName -print-settings $settings $file
   if($LASTEXITCODE -ne 0){throw "SumatraPDF exited with code $LASTEXITCODE."}
  } else {
   if($null -ne $job.page_start){throw "Page ranges are only supported for PDF files."}
   $helper=Join-Path $PSScriptRoot 'print-jpg.ps1'
   if(-not(Test-Path $helper)){throw "print-jpg.ps1 helper is missing."}
   & $helper -ImagePath $file -PrinterName $config.printerName -Copies ([int]$job.copies) -PaperSize $job.paper_size -ColorMode $job.color_mode
   if($LASTEXITCODE -ne 0){throw "JPG print helper failed."}
  }
  Invoke-RestMethod -Method Post -Uri "$($config.siteUrl)/api/agent/result" -Headers $headers -ContentType 'application/json' -Body (@{id=$job.id;status='completed';message='Submitted to the Windows print queue. Check the printer for physical output.'}|ConvertTo-Json)
  Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
 }catch{
  Write-Warning $_.Exception.Message
  if($job -and $job.id){
   try{Invoke-RestMethod -Method Post -Uri "$($config.siteUrl)/api/agent/result" -Headers $headers -ContentType 'application/json' -Body (@{id=$job.id;status='failed';message=$_.Exception.Message}|ConvertTo-Json)|Out-Null}catch{Write-Warning "Could not report job failure to server."}
  }
  if($file){Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
  Start-Sleep -Seconds 5
 }
 $job=$null;$file=$null
}
