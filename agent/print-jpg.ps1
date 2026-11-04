
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ImagePath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PrinterName,

    [ValidateRange(1, 5)]
    [int]$Copies = 1,

    [ValidateSet('A4', 'A5', 'A3', 'LETTER', 'LEGAL', 'B5')]
    [string]$PaperSize = 'A4',

    [ValidateSet('color', 'bw')]
    [string]$ColorMode = 'color'
)

$ErrorActionPreference = 'Stop'

$image = $null
$document = $null
$printPageHandler = $null

try {
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "Image file not found: $ImagePath"
    }

    $resolvedImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
    $extension = [IO.Path]::GetExtension($resolvedImagePath).ToLowerInvariant()

    if ($extension -notin @('.jpg', '.jpeg')) {
        throw "Only JPG/JPEG files are supported: $extension"
    }

    Add-Type -AssemblyName System.Drawing

    $image = [System.Drawing.Image]::FromFile($resolvedImagePath)

    $document = New-Object System.Drawing.Printing.PrintDocument
    $document.PrinterSettings.PrinterName = $PrinterName
    $document.PrinterSettings.Copies = [int16]$Copies

    if (-not $document.PrinterSettings.IsValid) {
        throw "Invalid printer queue: $PrinterName"
    }

    $paperKindName = switch ($PaperSize.ToUpperInvariant()) {
        'LETTER' { 'Letter' }
        'LEGAL'  { 'Legal' }
        default  { $PaperSize }
    }

    $paperKind = [System.Enum]::Parse(
        [System.Drawing.Printing.PaperKind],
        $paperKindName,
        $true
    )

    $matchingPaper = $null

    foreach ($availablePaper in $document.PrinterSettings.PaperSizes) {
        if (
            $availablePaper.Kind -eq $paperKind -or
            $availablePaper.PaperName -eq $paperKindName
        ) {
            $matchingPaper = $availablePaper
            break
        }
    }

    if ($null -eq $matchingPaper) {
        $availableNames = @(
            $document.PrinterSettings.PaperSizes |
            ForEach-Object { $_.PaperName }
        ) -join ', '

        throw "Paper size '$PaperSize' unavailable. Available: $availableNames"
    }

    $document.DefaultPageSettings.PaperSize = $matchingPaper
    $document.DefaultPageSettings.Color = ($ColorMode -eq 'color')
    $document.DefaultPageSettings.Landscape = ($image.Width -gt $image.Height)
    $document.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
    $document.OriginAtMargins = $false
    $document.DocumentName = [IO.Path]::GetFileName($resolvedImagePath)

    # Preserve the loaded image for the PrintPage event.
    $imageForPage = $image

    $printPageHandler = {
        param($sender, $eventArgs)

        $bounds = $eventArgs.MarginBounds

        if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
            $bounds = $eventArgs.PageBounds
        }

        # Fit the entire image inside the printable area.
        $scaleX = [double]$bounds.Width / [double]$imageForPage.Width
        $scaleY = [double]$bounds.Height / [double]$imageForPage.Height
        $scale = [Math]::Min($scaleX, $scaleY)

        $drawWidth = [Math]::Max(1, [int][Math]::Round($imageForPage.Width * $scale))
        $drawHeight = [Math]::Max(1, [int][Math]::Round($imageForPage.Height * $scale))

        $drawX = $bounds.Left + [int][Math]::Floor(($bounds.Width - $drawWidth) / 2)
        $drawY = $bounds.Top + [int][Math]::Floor(($bounds.Height - $drawHeight) / 2)

        $destination = New-Object System.Drawing.Rectangle(
            $drawX,
            $drawY,
            $drawWidth,
            $drawHeight
        )

        $eventArgs.Graphics.DrawImage($imageForPage, $destination)
        $eventArgs.HasMorePages = $false
    }.GetNewClosure()

    $document.add_PrintPage($printPageHandler)

    Write-Host "Submitting JPG print job..."
    Write-Host "File: $resolvedImagePath"
    Write-Host "Printer: $PrinterName"
    Write-Host "Paper: $PaperSize | Copies: $Copies | Mode: $ColorMode"

    $document.Print()

    Write-Host "JPG print job submitted successfully."
}
catch {
    Write-Error "JPG printing failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($null -ne $document) {
        if ($null -ne $printPageHandler) {
            try {
                $document.remove_PrintPage($printPageHandler)
            }
            catch {
                # Preserve the original printing error.
            }
        }

        $document.Dispose()
    }

    if ($null -ne $image) {
        $image.Dispose()
    }
}
