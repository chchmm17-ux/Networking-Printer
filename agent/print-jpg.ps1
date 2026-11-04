param(
    [Parameter(Mandatory=$true)][string]$ImagePath,
    [Parameter(Mandatory=$true)][string]$PrinterName,
    [ValidateRange(1,99)][int]$Copies = 1,
    [ValidateSet('A4','A5','A3','LETTER','LEGAL','B5')][string]$PaperSize = 'A4',
    [ValidateSet('color','bw')][string]$ColorMode = 'color'
)

$ErrorActionPreference = 'Stop'
$image = $null
$document = $null

try {
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "The uploaded JPG temporary file was not found."
    }

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($ImagePath)

    $document = New-Object System.Drawing.Printing.PrintDocument
    $document.PrinterSettings.PrinterName = $PrinterName

    if (-not $document.PrinterSettings.IsValid) {
        throw "Windows cannot find or use printer queue '$PrinterName'."
    }

    # Match the selected standard paper size against the sizes exposed by the Brother driver.
    $paperKindName = switch ($PaperSize) {
        'LETTER' { 'Letter' }
        'LEGAL'  { 'Legal' }
        default  { $PaperSize }
    }
    $paperKind = [System.Enum]::Parse([System.Drawing.Printing.PaperKind], $paperKindName, $true)
    $matchingPaper = $null

    foreach ($availablePaper in $document.PrinterSettings.PaperSizes) {
        if ($availablePaper.Kind -eq $paperKind) {
            $matchingPaper = $availablePaper
            break
        }
    }

    if ($null -eq $matchingPaper) {
        $availableNames = @($document.PrinterSettings.PaperSizes | ForEach-Object { $_.PaperName }) -join ', '
        throw "The Brother driver does not report paper size '$PaperSize'. Available sizes: $availableNames"
    }

    $document.PrinterSettings.Copies = [int16]$Copies
    $document.DefaultPageSettings.PaperSize = $matchingPaper
    $document.DefaultPageSettings.Color = ($ColorMode -eq 'color')
    $document.DefaultPageSettings.Landscape = ($image.Width -gt $image.Height)
    $document.DocumentName = [System.IO.Path]::GetFileName($ImagePath)
    $document.OriginAtMargins = $false

    $imageForPage = $image
    $handler = [System.Drawing.Printing.PrintPageEventHandler]{
        param($sender, $eventArgs)

        $bounds = $eventArgs.MarginBounds
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
            $bounds = $eventArgs.PageBounds
        }

        $scaleX = $bounds.Width / [double]$imageForPage.Width
        $scaleY = $bounds.Height / [double]$imageForPage.Height
        $scale = [Math]::Min($scaleX, $scaleY)

        $drawWidth = [int][Math]::Round($imageForPage.Width * $scale)
        $drawHeight = [int][Math]::Round($imageForPage.Height * $scale)
        $left = $bounds.Left + [int](($bounds.Width - $drawWidth) / 2)
        $top = $bounds.Top + [int](($bounds.Height - $drawHeight) / 2)

        $destination = New-Object System.Drawing.Rectangle($left, $top, $drawWidth, $drawHeight)
        $eventArgs.Graphics.DrawImage($imageForPage, $destination)
        $eventArgs.HasMorePages = $false
    }

    $document.add_PrintPage($handler)
    $document.Print()
    Write-Output "JPG submitted to '$PrinterName' using $PaperSize and $ColorMode."
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    if ($document -ne $null) { $document.Dispose() }
    if ($image -ne $null) { $image.Dispose() }
}
