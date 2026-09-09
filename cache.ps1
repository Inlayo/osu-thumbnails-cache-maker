#requires -version 5.1

<#
    GenerateOsuThumbnails.ps1

    osu!stable Data\bt thumbnail generator

    Directory layout:

    osu!\
        ├── Songs\
        ├── Data\
        │   └── bt\
        └── GenerateOsuThumbnails.ps1

    Generates:

    Data\bt\<BeatmapSetID>.jpg
    Data\bt\<BeatmapSetID>l.jpg

    Sizes:

    <ID>.jpg   = 80x60
    <ID>l.jpg  = 160x120

    BeatmapSetID detection priority:

    1. BeatmapSetID from .osu file
    2. Leading number from mapset folder name
    3. No SetID

    Background selection:

    When a mapset contains multiple beatmaps,
    the background from the beatmap with the LOWEST BeatmapID
    is used for the thumbnail.

    Example:

    BeatmapID 100001 -> background A
    BeatmapID 100002 -> background B
    BeatmapID 100003 -> background C

    Result:
    background A is used.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$SmallWidth  = 80
$SmallHeight = 60

$LargeWidth  = 160
$LargeHeight = 120

# JPEG quality.
# 90 is a good compromise between size and quality.
$JpegQuality = 90


# ------------------------------------------------------------
# Locate osu! directory
# ------------------------------------------------------------

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition

# If the script is directly inside the osu! folder,
# this will be the osu! root.
$OsuRoot = $ScriptDirectory

$SongsDirectory = Join-Path $OsuRoot 'Songs'
$DataDirectory  = Join-Path $OsuRoot 'Data'
$ThumbnailDirectory = Join-Path $DataDirectory 'bt'

if (-not (Test-Path -LiteralPath $SongsDirectory -PathType Container)) {

    Write-Host ""
    Write-Host "Songs folder was not found:" -ForegroundColor Red
    Write-Host "  $SongsDirectory"
    Write-Host ""

    Write-Host "The script should normally be placed here:" -ForegroundColor Yellow
    Write-Host "  C:\osu!\GenerateOsuThumbnails.ps1"
    Write-Host ""

    exit 1
}


# Create Data\bt if necessary.
if (-not (Test-Path -LiteralPath $ThumbnailDirectory -PathType Container)) {

    Write-Host "Creating thumbnail directory:"
    Write-Host "  $ThumbnailDirectory"
    Write-Host ""

    New-Item -ItemType Directory -Path $ThumbnailDirectory -Force | Out-Null
}


# ------------------------------------------------------------
# Load System.Drawing
# ------------------------------------------------------------

try {

    Add-Type -AssemblyName System.Drawing

}
catch {

    Write-Host ""
    Write-Host "Unable to load System.Drawing." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""

    exit 1
}


# ------------------------------------------------------------
# Helper: JPEG encoder
# ------------------------------------------------------------

function Get-JpegCodec {

    $codecs = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()

    foreach ($codec in $codecs) {

        if ($codec.MimeType -eq 'image/jpeg') {
            return $codec
        }
    }

    throw "JPEG encoder was not found."
}

$JpegCodec = Get-JpegCodec


# ------------------------------------------------------------
# Helper: create JPEG encoder parameters
# ------------------------------------------------------------

function New-JpegParameters {

    param(
        [int]$Quality
    )

    $parameters = New-Object System.Drawing.Imaging.EncoderParameters(1)

    $qualityParameter = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality,
        [long]$Quality
    )

    $parameters.Param[0] = $qualityParameter

    return $parameters
}


# ------------------------------------------------------------
# Helper: safely dispose image
# ------------------------------------------------------------

function Dispose-Image {

    param(
        [System.Drawing.Image]$Image
    )

    if ($null -ne $Image) {

        try {
            $Image.Dispose()
        }
        catch {
        }
    }
}


# ------------------------------------------------------------
# Helper: determine whether an extension is an image
# ------------------------------------------------------------

function Test-ImageExtension {

    param(
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path)

    if ([string]::IsNullOrWhiteSpace($extension)) {
        return $false
    }

    switch ($extension.ToLowerInvariant()) {

        '.jpg'  { return $true }
        '.jpeg' { return $true }
        '.png'  { return $true }
        '.bmp'  { return $true }
        '.gif'  { return $true }
        '.tif'  { return $true }
        '.tiff' { return $true }

        default { return $false }
    }
}


# ------------------------------------------------------------
# Helper: find background references in .osu file
# ------------------------------------------------------------

function Get-BackgroundReferences {

    param(
        [string]$OsuFile
    )

    $results = New-Object System.Collections.Generic.List[string]

    $inEvents = $false

    try {

        $lines = [System.IO.File]::ReadAllLines(
            $OsuFile,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {

        # Some old files can contain unusual encoding.
        # Fall back to default Windows encoding.
        $lines = [System.IO.File]::ReadAllLines($OsuFile)
    }

    foreach ($line in $lines) {

        $trimmed = $line.Trim()

        if ($trimmed -eq '[Events]') {

            $inEvents = $true
            continue
        }

        # Stop once another section starts.
        if ($inEvents -and
            $trimmed.StartsWith('[') -and
            $trimmed.EndsWith(']')) {

            break
        }

        if (-not $inEvents) {
            continue
        }

        # Normal osu! background entry:
        #
        # 0,0,"background.jpg",0,0
        #
        # We only care about the quoted filename.

        if ($trimmed -match '^\s*0\s*,\s*0\s*,\s*"([^"]+)"') {

            $filename = $Matches[1]

            if ([string]::IsNullOrWhiteSpace($filename)) {
                continue
            }

            # Ignore videos.
            if ($filename -match '\.(mp4|avi|webm|mov|mkv)$') {
                continue
            }

            if (Test-ImageExtension $filename) {

                if (-not $results.Contains($filename)) {
                    $results.Add($filename)
                }
            }
        }
    }

    return $results
}


# ------------------------------------------------------------
# Helper: normalize filename from osu! Events
# ------------------------------------------------------------

function Convert-OsuRelativePath {

    param(
        [string]$Filename
    )

    # osu! uses / in .osu files even on Windows.
    $normalized = $Filename.Replace('/', '\')

    # Remove leading path separators.
    while ($normalized.StartsWith('\')) {
        $normalized = $normalized.Substring(1)
    }

    return $normalized
}


# ------------------------------------------------------------
# Helper: get BeatmapSetID from an .osu file
# ------------------------------------------------------------

function Get-BeatmapSetId {

    param(
        [string]$OsuFile
    )

    try {

        $lines = [System.IO.File]::ReadAllLines(
            $OsuFile,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {

        $lines = [System.IO.File]::ReadAllLines($OsuFile)
    }

    foreach ($line in $lines) {

        if ($line -match '^\s*BeatmapSetID\s*:\s*(-?\d+)') {
            return [int64]$Matches[1]
        }
    }

    return $null
}


# ------------------------------------------------------------
# Helper: get BeatmapID from an .osu file
# ------------------------------------------------------------

function Get-BeatmapId {

    param(
        [string]$OsuFile
    )

    try {

        $lines = [System.IO.File]::ReadAllLines(
            $OsuFile,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {

        $lines = [System.IO.File]::ReadAllLines($OsuFile)
    }

    foreach ($line in $lines) {

        if ($line -match '^\s*BeatmapID\s*:\s*(\d+)') {
            return [int64]$Matches[1]
        }
    }

    return $null
}


# ------------------------------------------------------------
# Helper: get BeatmapSetID from mapset directory name
# ------------------------------------------------------------

function Get-BeatmapSetIdFromFolderName {

    param(
        [System.IO.DirectoryInfo]$MapsetDirectory
    )

    $folderName = $MapsetDirectory.Name

    # --------------------------------------------------------
    # Only accept a number at the BEGINNING of the folder name.
    #
    # Valid examples:
    #
    #   10143 IOSYS - Marisa...
    #   10143_IOSYS...
    #   10143-IOSYS...
    #   10143
    #
    # Invalid examples:
    #
    #   IOSYS 10143...
    #   Map10143...
    #   abc10143...
    #   123abc...
    #
    # The separator after the number must be:
    #
    #   whitespace
    #   underscore
    #   hyphen
    #   end of string
    # --------------------------------------------------------

    if ($folderName -match '^\s*(\d+)(?:\s+|_|-|$)') {

        try {

            $id = [int64]$Matches[1]

            if ($id -gt 0) {
                return $id
            }
        }
        catch {

            return $null
        }
    }

    return $null
}


# ------------------------------------------------------------
# Helper: get all valid SetIDs from a mapset directory
# ------------------------------------------------------------

function Get-MapsetIdInformation {

    param(
        [System.IO.DirectoryInfo]$MapsetDirectory,

        [System.IO.FileInfo[]]$OsuFiles
    )

    $validIds = New-Object System.Collections.Generic.List[int64]

    $allIds = New-Object System.Collections.Generic.List[int64]

    # --------------------------------------------------------
    # First:
    #
    # Read BeatmapSetID from every .osu file.
    # --------------------------------------------------------

    foreach ($osuFile in $OsuFiles) {

        $id = Get-BeatmapSetId $osuFile.FullName

        if ($null -eq $id) {
            continue
        }

        $allIds.Add($id)

        # -1 means not assigned.
        if ($id -gt 0) {
            $validIds.Add($id)
        }
    }


    # --------------------------------------------------------
    # Normal case:
    #
    # At least one valid BeatmapSetID was found.
    #
    # The .osu value ALWAYS has priority over the folder name.
    # --------------------------------------------------------

    if ($validIds.Count -gt 0) {

        # Count each ID.
        $groups = $validIds |
            Group-Object |
            Sort-Object Count -Descending

        $selectedId = [int64]$groups[0].Name

        # If multiple different valid IDs exist in the same
        # directory, record it as a conflict.
        $conflict = ($groups.Count -gt 1)

        return [PSCustomObject]@{
            SetId        = $selectedId
            AllIds       = $allIds
            ValidIds     = $validIds
            HadMinusOne  = ($allIds -contains -1)
            Conflict     = $conflict
            Source       = 'OsuFile'
        }
    }


    # --------------------------------------------------------
    # Fallback:
    #
    # No valid BeatmapSetID exists in any .osu file.
    #
    # Try to get the ID from the mapset folder name.
    # --------------------------------------------------------

    $folderId = Get-BeatmapSetIdFromFolderName $MapsetDirectory

    if ($null -ne $folderId) {

        $validIds.Add($folderId)

        return [PSCustomObject]@{
            SetId        = $folderId
            AllIds       = $allIds
            ValidIds     = $validIds
            HadMinusOne  = ($allIds -contains -1)
            Conflict     = $false
            Source       = 'FolderName'
        }
    }


    # --------------------------------------------------------
    # No valid ID anywhere.
    # --------------------------------------------------------

    return [PSCustomObject]@{
        SetId        = $null
        AllIds       = $allIds
        ValidIds     = $validIds
        HadMinusOne  = ($allIds -contains -1)
        Conflict     = $false
        Source       = 'None'
    }
}


# ------------------------------------------------------------
# Helper: locate the background image for a mapset
#
# IMPORTANT:
#
# If multiple beatmaps exist in the same mapset,
# the beatmap with the LOWEST BeatmapID is selected first.
#
# Example:
#
#   BeatmapID 500 -> background A
#   BeatmapID 300 -> background B
#   BeatmapID 400 -> background C
#
# Result:
#
#   background B
# ------------------------------------------------------------

function Find-MapsetBackground {

    param(
        [System.IO.DirectoryInfo]$MapsetDirectory,

        [System.IO.FileInfo[]]$OsuFiles
    )


    # --------------------------------------------------------
    # Collect BeatmapID information from every .osu file.
    # --------------------------------------------------------

    $beatmapFiles = New-Object System.Collections.Generic.List[object]

    foreach ($osuFile in $OsuFiles) {

        $beatmapId = Get-BeatmapId $osuFile.FullName

        if ($null -eq $beatmapId) {
            continue
        }

        if ($beatmapId -le 0) {
            continue
        }

        $beatmapFiles.Add(
            [PSCustomObject]@{
                File      = $osuFile
                BeatmapID = $beatmapId
            }
        )
    }


    # --------------------------------------------------------
    # Sort by BeatmapID.
    #
    # Lowest BeatmapID comes first.
    # --------------------------------------------------------

    $sortedBeatmaps = @(
        $beatmapFiles |
            Sort-Object BeatmapID
    )


    # --------------------------------------------------------
    # Try backgrounds in BeatmapID order.
    # --------------------------------------------------------

    foreach ($beatmap in $sortedBeatmaps) {

        $osuFile = $beatmap.File

        $backgrounds = Get-BackgroundReferences $osuFile.FullName

        foreach ($background in $backgrounds) {

            $relativePath = Convert-OsuRelativePath $background

            $candidate = Join-Path `
                $MapsetDirectory.FullName `
                $relativePath

            if (Test-Path -LiteralPath $candidate -PathType Leaf) {

                try {

                    # Make sure the image can actually be decoded.
                    $testImage = [System.Drawing.Image]::FromFile(
                        $candidate
                    )

                    $width  = $testImage.Width
                    $height = $testImage.Height

                    $testImage.Dispose()

                    if ($width -gt 0 -and $height -gt 0) {

                        return [PSCustomObject]@{
                            Path        = $candidate
                            Relative    = $relativePath
                            SourceOsu   = $osuFile.FullName
                            BeatmapID   = $beatmap.BeatmapID
                            Width       = $width
                            Height      = $height
                        }
                    }
                }
                catch {

                    # Background exists but cannot be decoded.
                    continue
                }
            }
        }
    }


    # --------------------------------------------------------
    # Fallback:
    #
    # Some malformed maps may not have a BeatmapID.
    #
    # In that case, inspect .osu files in their original order.
    # --------------------------------------------------------

    foreach ($osuFile in $OsuFiles) {

        $backgrounds = Get-BackgroundReferences $osuFile.FullName

        foreach ($background in $backgrounds) {

            $relativePath = Convert-OsuRelativePath $background

            $candidate = Join-Path `
                $MapsetDirectory.FullName `
                $relativePath

            if (Test-Path -LiteralPath $candidate -PathType Leaf) {

                try {

                    $testImage = [System.Drawing.Image]::FromFile(
                        $candidate
                    )

                    $width  = $testImage.Width
                    $height = $testImage.Height

                    $testImage.Dispose()

                    if ($width -gt 0 -and $height -gt 0) {

                        return [PSCustomObject]@{
                            Path        = $candidate
                            Relative    = $relativePath
                            SourceOsu   = $osuFile.FullName
                            BeatmapID   = $null
                            Width       = $width
                            Height      = $height
                        }
                    }
                }
                catch {

                    continue
                }
            }
        }
    }


    # --------------------------------------------------------
    # Final fallback:
    #
    # Some malformed maps may not have a usable [Events]
    # background declaration.
    #
    # Look for image files directly.
    # --------------------------------------------------------

    try {

        $images = Get-ChildItem `
            -LiteralPath $MapsetDirectory.FullName `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object {
                Test-ImageExtension $_.FullName
            }

        foreach ($image in $images) {

            try {

                $testImage = [System.Drawing.Image]::FromFile(
                    $image.FullName
                )

                $width  = $testImage.Width
                $height = $testImage.Height

                $testImage.Dispose()

                if ($width -gt 0 -and $height -gt 0) {

                    return [PSCustomObject]@{
                        Path        = $image.FullName
                        Relative    = $image.FullName.Substring(
                            $MapsetDirectory.FullName.Length
                        ).TrimStart('\')
                        SourceOsu   = $null
                        BeatmapID   = $null
                        Width       = $width
                        Height      = $height
                    }
                }
            }
            catch {

                continue
            }
        }
    }
    catch {
    }


    return $null
}


# ------------------------------------------------------------
# Helper: create a 4:3 thumbnail
# ------------------------------------------------------------

function New-ThumbnailImage {

    param(
        [System.Drawing.Image]$SourceImage,
        [int]$TargetWidth,
        [int]$TargetHeight
    )

    $sourceWidth  = $SourceImage.Width
    $sourceHeight = $SourceImage.Height

    if ($sourceWidth -le 0 -or $sourceHeight -le 0) {
        throw "Invalid source image dimensions."
    }

    # Calculate crop rectangle that exactly matches target aspect ratio.
    $sourceAspect = $sourceWidth / [double]$sourceHeight
    $targetAspect = $TargetWidth / [double]$TargetHeight

    [int]$cropX = 0
    [int]$cropY = 0
    [int]$cropWidth = $sourceWidth
    [int]$cropHeight = $sourceHeight

    if ($sourceAspect -gt $targetAspect) {

        # Source is wider.
        $cropWidth = [int][Math]::Round(
            $sourceHeight * $targetAspect
        )

        $cropX = [int][Math]::Round(
            ($sourceWidth - $cropWidth) / 2.0
        )
    }
    elseif ($sourceAspect -lt $targetAspect) {

        # Source is taller.
        $cropHeight = [int][Math]::Round(
            $sourceWidth / $targetAspect
        )

        $cropY = [int][Math]::Round(
            ($sourceHeight - $cropHeight) / 2.0
        )
    }

    $bitmap = New-Object System.Drawing.Bitmap(
        $TargetWidth,
        $TargetHeight,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )

    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {

        $graphics.CompositingMode =
            [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

        $graphics.CompositingQuality =
            [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $graphics.InterpolationMode =
            [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $graphics.SmoothingMode =
            [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $graphics.PixelOffsetMode =
            [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $graphics.DrawImage(
            $SourceImage,
            [System.Drawing.Rectangle]::new(
                0,
                0,
                $TargetWidth,
                $TargetHeight
            ),
            $cropX,
            $cropY,
            $cropWidth,
            $cropHeight,
            [System.Drawing.GraphicsUnit]::Pixel
        )
    }
    finally {

        $graphics.Dispose()
    }

    return $bitmap
}


# ------------------------------------------------------------
# Helper: write JPEG atomically
# ------------------------------------------------------------

function Save-JpegAtomic {

    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutputPath,
        [int]$Quality
    )

    $directory = Split-Path -Parent $OutputPath

    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {

        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Temporary file in the same directory.
    # This prevents a partially-written JPEG from becoming the cache.
    $temporaryPath = $OutputPath + '.tmp'

    if (Test-Path -LiteralPath $temporaryPath) {

        try {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        catch {
        }
    }

    $encoderParameters = New-JpegParameters $Quality

    try {

        $Bitmap.Save(
            $temporaryPath,
            $JpegCodec,
            $encoderParameters
        )

        # Replace existing file.
        if (Test-Path -LiteralPath $OutputPath) {

            Remove-Item -LiteralPath $OutputPath -Force
        }

        Move-Item `
            -LiteralPath $temporaryPath `
            -Destination $OutputPath `
            -Force
    }
    finally {

        $encoderParameters.Dispose()

        if (Test-Path -LiteralPath $temporaryPath) {

            try {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
            catch {
            }
        }
    }
}


# ------------------------------------------------------------
# Helper: validate existing thumbnail
# ------------------------------------------------------------

function Test-Thumbnail {

    param(
        [string]$Path,
        [int]$ExpectedWidth,
        [int]$ExpectedHeight
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $image = $null

    try {

        $image = [System.Drawing.Image]::FromFile($Path)

        if ($image.Width -ne $ExpectedWidth) {
            return $false
        }

        if ($image.Height -ne $ExpectedHeight) {
            return $false
        }

        # Make sure it is actually readable.
        $null = $image.RawFormat

        return $true
    }
    catch {

        return $false
    }
    finally {

        if ($null -ne $image) {
            $image.Dispose()
        }
    }
}


# ------------------------------------------------------------
# Select operation
# ------------------------------------------------------------

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       osu! Thumbnail Cache Generator" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "osu! root:"
Write-Host "  $OsuRoot"
Write-Host ""

Write-Host "Songs:"
Write-Host "  $SongsDirectory"
Write-Host ""

Write-Host "Thumbnail cache:"
Write-Host "  $ThumbnailDirectory"
Write-Host ""

Write-Host "1 = Create missing thumbnails only"
Write-Host "2 = Regenerate ALL thumbnails"
Write-Host "3 = Create missing / repair invalid thumbnails"
Write-Host ""

$mode = Read-Host "Select mode"

switch ($mode) {

    '1' {
        $Operation = 'Missing'
    }

    '2' {
        $Operation = 'All'
    }

    '3' {
        $Operation = 'Repair'
    }

    default {

        Write-Host ""
        Write-Host "Invalid selection." -ForegroundColor Red
        exit 1
    }
}


# ------------------------------------------------------------
# Log files
# ------------------------------------------------------------

$LogDirectory = Join-Path $OsuRoot 'ThumbnailGeneratorLogs'

if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {

    New-Item `
        -ItemType Directory `
        -Path $LogDirectory `
        -Force |
        Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$FailedLog = Join-Path `
    $LogDirectory `
    "thumbnail_failed_$timestamp.txt"

$MinusOneLog = Join-Path `
    $LogDirectory `
    "minus_one_fixed_$timestamp.txt"

$ConflictLog = Join-Path `
    $LogDirectory `
    "setid_conflicts_$timestamp.txt"

$NoBackgroundLog = Join-Path `
    $LogDirectory `
    "no_background_$timestamp.txt"

$FolderIdLog = Join-Path `
    $LogDirectory `
    "folder_name_setid_$timestamp.txt"


# ------------------------------------------------------------
# Statistics
# ------------------------------------------------------------

$Stats = [ordered]@{

    MapsetsScanned      = 0
    BeatmapsScanned     = 0

    Created             = 0
    Skipped             = 0
    Repaired            = 0

    MinusOneFixed       = 0
    FolderNameIds       = 0
    SetIdConflicts      = 0

    NoBackground        = 0
    NoSetId             = 0

    UnsupportedImage    = 0
    Failed              = 0
}

$StartTime = Get-Date


# ------------------------------------------------------------
# Find mapset directories
# ------------------------------------------------------------

Write-Host ""
Write-Host "Scanning Songs..." -ForegroundColor Cyan
Write-Host ""

$mapsetDirectories = Get-ChildItem `
    -LiteralPath $SongsDirectory `
    -Directory `
    -Recurse `
    -ErrorAction SilentlyContinue

$totalDirectories = $mapsetDirectories.Count

$currentDirectoryIndex = 0


# ------------------------------------------------------------
# Process every directory containing .osu files
# ------------------------------------------------------------

foreach ($mapsetDirectory in $mapsetDirectories) {

    $currentDirectoryIndex++

    $osuFiles = @(Get-ChildItem `
        -LiteralPath $mapsetDirectory.FullName `
        -Filter '*.osu' `
        -File `
        -ErrorAction SilentlyContinue)

    if ($osuFiles.Count -eq 0) {
        continue
    }

    $Stats.MapsetsScanned++
    $Stats.BeatmapsScanned += $osuFiles.Count


    # --------------------------------------------------------
    # Progress
    # --------------------------------------------------------

    $percent = 0

    if ($totalDirectories -gt 0) {

        $percent = [int]((
            $currentDirectoryIndex /
            [double]$totalDirectories
        ) * 100)
    }

    Write-Progress `
        -Activity "Generating osu! thumbnails" `
        -Status "$currentDirectoryIndex / $totalDirectories : $($mapsetDirectory.Name)" `
        -PercentComplete $percent


    # --------------------------------------------------------
    # Determine SetID
    # --------------------------------------------------------

    try {

        # IMPORTANT:
        # Pass both the mapset directory and .osu files.
        #
        # The function will:
        #
        # 1. Search .osu BeatmapSetID
        # 2. If none is valid, inspect folder name
        # 3. Otherwise return no SetID

        $idInfo = Get-MapsetIdInformation `
            $mapsetDirectory `
            $osuFiles

        $setId = $idInfo.SetId

        if ($null -eq $setId) {

            $Stats.NoSetId++

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "NO SETID: $($mapsetDirectory.FullName)"

            continue
        }


        # ----------------------------------------------------
        # Record folder-name fallback
        # ----------------------------------------------------

        if ($idInfo.Source -eq 'FolderName') {

            $Stats.FolderNameIds++

            Add-Content `
                -LiteralPath $FolderIdLog `
                -Value "$setId`t$($mapsetDirectory.FullName)"
        }


        # ----------------------------------------------------
        # Handle -1 SetID
        # ----------------------------------------------------

        if ($idInfo.HadMinusOne) {

            $Stats.MinusOneFixed++

            Add-Content `
                -LiteralPath $MinusOneLog `
                -Value "$setId`t$($mapsetDirectory.FullName)"
        }


        # ----------------------------------------------------
        # Handle SetID conflicts
        # ----------------------------------------------------

        if ($idInfo.Conflict) {

            $Stats.SetIdConflicts++

            $idsString = (
                $idInfo.ValidIds |
                Sort-Object -Unique
            ) -join ', '

            Add-Content `
                -LiteralPath $ConflictLog `
                -Value "SELECTED=$setId`tIDS=$idsString`tPATH=$($mapsetDirectory.FullName)"
        }


        # ----------------------------------------------------
        # Output paths
        # ----------------------------------------------------

        $smallOutput = Join-Path `
            $ThumbnailDirectory `
            "$setId.jpg"

        $largeOutput = Join-Path `
            $ThumbnailDirectory `
            "${setId}l.jpg"


        # ----------------------------------------------------
        # Determine cache state
        # ----------------------------------------------------

        $smallValid = Test-Thumbnail `
            $smallOutput `
            $SmallWidth `
            $SmallHeight

        $largeValid = Test-Thumbnail `
            $largeOutput `
            $LargeWidth `
            $LargeHeight


        if ($Operation -eq 'Missing') {

            if ($smallValid -and $largeValid) {

                $Stats.Skipped++
                continue
            }
        }


        if ($Operation -eq 'Repair') {

            if ($smallValid -and $largeValid) {

                $Stats.Skipped++
                continue
            }
        }


        # ----------------------------------------------------
        # Find background
        #
        # The lowest BeatmapID is used here.
        # ----------------------------------------------------

        $background = Find-MapsetBackground `
            $mapsetDirectory `
            $osuFiles

        if ($null -eq $background) {

            $Stats.NoBackground++

            Add-Content `
                -LiteralPath $NoBackgroundLog `
                -Value $mapsetDirectory.FullName

            continue
        }


        # ----------------------------------------------------
        # Load source image
        # ----------------------------------------------------

        $sourceImage = $null
        $smallBitmap = $null
        $largeBitmap = $null

        try {

            $sourceImage = [System.Drawing.Image]::FromFile(
                $background.Path
            )


            # ------------------------------------------------
            # Generate large thumbnail
            # ------------------------------------------------

            $largeBitmap = New-ThumbnailImage `
                $sourceImage `
                $LargeWidth `
                $LargeHeight


            # ------------------------------------------------
            # Generate small thumbnail
            # ------------------------------------------------

            $smallBitmap = New-ThumbnailImage `
                $sourceImage `
                $SmallWidth `
                $SmallHeight


            # ------------------------------------------------
            # Save according to operation
            # ------------------------------------------------

            $shouldWriteSmall = $true
            $shouldWriteLarge = $true

            if ($Operation -eq 'Missing') {

                if ($smallValid) {
                    $shouldWriteSmall = $false
                }

                if ($largeValid) {
                    $shouldWriteLarge = $false
                }
            }


            if ($Operation -eq 'Repair') {

                if ($smallValid) {
                    $shouldWriteSmall = $false
                }

                if ($largeValid) {
                    $shouldWriteLarge = $false
                }
            }


            if ($shouldWriteLarge) {

                Save-JpegAtomic `
                    $largeBitmap `
                    $largeOutput `
                    $JpegQuality
            }


            if ($shouldWriteSmall) {

                Save-JpegAtomic `
                    $smallBitmap `
                    $smallOutput `
                    $JpegQuality
            }


            # ------------------------------------------------
            # Verify generated files
            # ------------------------------------------------

            $verifiedSmall = Test-Thumbnail `
                $smallOutput `
                $SmallWidth `
                $SmallHeight

            $verifiedLarge = Test-Thumbnail `
                $largeOutput `
                $LargeWidth `
                $LargeHeight

            if (-not $verifiedSmall -or -not $verifiedLarge) {

                throw "Generated thumbnail failed verification."
            }


            if ($Operation -eq 'Repair' -and
                (-not $smallValid -or -not $largeValid)) {

                $Stats.Repaired++
            }
            else {

                $Stats.Created++
            }
        }
        catch {

            $Stats.Failed++

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "FAILED: $($mapsetDirectory.FullName)"

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "  SetID: $setId"

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "  SetID source: $($idInfo.Source)"

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "  Background: $($background.Path)"

            Add-Content `
                -LiteralPath $FailedLog `
                -Value "  Error: $($_.Exception.Message)"

            Add-Content `
                -LiteralPath $FailedLog `
                -Value ""
        }
        finally {

            if ($null -ne $smallBitmap) {

                try {
                    $smallBitmap.Dispose()
                }
                catch {
                }
            }


            if ($null -ne $largeBitmap) {

                try {
                    $largeBitmap.Dispose()
                }
                catch {
                }
            }


            if ($null -ne $sourceImage) {

                try {
                    $sourceImage.Dispose()
                }
                catch {
                }
            }
        }
    }
    catch {

        $Stats.Failed++

        Add-Content `
            -LiteralPath $FailedLog `
            -Value "FAILED MAPSET: $($mapsetDirectory.FullName)"

        Add-Content `
            -LiteralPath $FailedLog `
            -Value "ERROR: $($_.Exception.Message)"

        Add-Content `
            -LiteralPath $FailedLog `
            -Value ""
    }
}


# ------------------------------------------------------------
# Finish progress
# ------------------------------------------------------------

Write-Progress `
    -Activity "Generating osu! thumbnails" `
    -Completed


# ------------------------------------------------------------
# Final statistics
# ------------------------------------------------------------

$EndTime = Get-Date
$Elapsed = $EndTime - $StartTime

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "                 COMPLETE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host ("Mapsets scanned : {0}" -f $Stats.MapsetsScanned)
Write-Host ("Beatmaps scanned: {0}" -f $Stats.BeatmapsScanned)
Write-Host ""

Write-Host ("Created         : {0}" -f $Stats.Created)
Write-Host ("Repaired        : {0}" -f $Stats.Repaired)
Write-Host ("Skipped         : {0}" -f $Stats.Skipped)
Write-Host ""

Write-Host ("-1 SetID fixed  : {0}" -f $Stats.MinusOneFixed)
Write-Host ("Folder name IDs : {0}" -f $Stats.FolderNameIds)
Write-Host ("SetID conflicts : {0}" -f $Stats.SetIdConflicts)
Write-Host ""

Write-Host ("No SetID        : {0}" -f $Stats.NoSetId)
Write-Host ("No background   : {0}" -f $Stats.NoBackground)
Write-Host ("Failed          : {0}" -f $Stats.Failed)
Write-Host ""

Write-Host ("Elapsed time    : {0}" -f $Elapsed.ToString())
Write-Host ""

Write-Host "Output:"
Write-Host "  $ThumbnailDirectory"
Write-Host ""

Write-Host "Logs:"
Write-Host "  $LogDirectory"
Write-Host ""


# ------------------------------------------------------------
# Log summary
# ------------------------------------------------------------

$summaryFile = Join-Path `
    $LogDirectory `
    "summary_$timestamp.txt"

$summary = @"
osu! Thumbnail Cache Generator
==============================

Started:
$StartTime

Finished:
$EndTime

Elapsed:
$Elapsed

Mapsets scanned:
$($Stats.MapsetsScanned)

Beatmaps scanned:
$($Stats.BeatmapsScanned)

Created:
$($Stats.Created)

Repaired:
$($Stats.Repaired)

Skipped:
$($Stats.Skipped)

-1 SetID fixed:
$($Stats.MinusOneFixed)

Folder name IDs:
$($Stats.FolderNameIds)

SetID conflicts:
$($Stats.SetIdConflicts)

No SetID:
$($Stats.NoSetId)

No background:
$($Stats.NoBackground)

Failed:
$($Stats.Failed)

Thumbnail directory:
$ThumbnailDirectory
"@

Set-Content `
    -LiteralPath $summaryFile `
    -Value $summary `
    -Encoding UTF8

Write-Host "Summary saved to:"
Write-Host "  $summaryFile"
Write-Host ""


if ($Stats.Failed -gt 0) {

    Write-Host "There were errors." -ForegroundColor Yellow
    Write-Host "Check:"
    Write-Host "  $FailedLog"
    Write-Host ""
}


if ($Stats.NoSetId -gt 0) {

    Write-Host "Some mapsets had no valid BeatmapSetID." -ForegroundColor Yellow
    Write-Host "These cannot safely be written to Data\bt."
    Write-Host ""
}


if ($Stats.FolderNameIds -gt 0) {

    Write-Host "Some SetIDs were recovered from folder names." -ForegroundColor Green
    Write-Host "Check:"
    Write-Host "  $FolderIdLog"
    Write-Host ""
}


Write-Host "Done." -ForegroundColor Green
