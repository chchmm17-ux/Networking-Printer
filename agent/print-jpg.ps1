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
        throw "The JPG temporary file was not found: $ImagePath"
    }

    $resolvedImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
    $extension = [System.IO.Path]::GetExtension($resolvedImagePath).ToLowerInvariant()
    if ($extension -notin @('.jpg', '.jpeg')) {
        throw "Only JPG/JPEG images are supported. Received: $extension"
    }

    Add-Type -AssemblyName System.Drawing

    $image = [System.Drawing.Image]::FromFile($resolvedImagePath)

    $document = New-Object System.Drawing.Printing.PrintDocument
    $document.PrinterSettings.PrinterName = $PrinterName
    $document.PrinterSettings.Copies = [int16]$Copies

    if (-not $document.PrinterSettings.IsValid) {
        throw "Windows cannot find or use printer queue '$PrinterName'. Check the exact queue name and make sure the printer is installed."
    }

    # Map the website's paper-size labels to the Windows PaperKind enum.
    $paperKindName = switch ($PaperSize.ToUpperInvariant()) {
        'LETTER' { 'Letter'; break }
        'LEGAL'  { 'Legal'; break }
        default  { $PaperSize; break }
    }

    try {
        $paperKind = [System.Enum]::Parse(
            [System.Drawing.Printing.PaperKind],
            $paperKindName,
            $true
        )
    }
    catch {
        throw "Windows does not recognize paper size '$PaperSize'."
    }

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

        throw "The printer driver does not offer '$PaperSize'. Available sizes: $availableNames"
    }

    $document.DefaultPageSettings.PaperSize = $matchingPaper
    $document.DefaultPageSettings.Color = ($ColorMode -eq 'color')
    $document.DefaultPageSettings.Landscape = ($image.Width -gt $image.Height)
    $document.OriginAtMargins = $false
    $document.DocumentName = [System.IO.Path]::GetFileName($resolvedImagePath)

    # Capture the image in the event-handler scope so it remains available
    # when Windows raises the PrintPage event.
    $imageForPage = $image
