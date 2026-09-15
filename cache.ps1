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


    ============================================================
    MAIN BEATMAP SELECTION RULE
    ============================================================

    Star Rating is NOT read or calculated.

    osu!stable .osu source files do not directly contain the
    displayed Star Rating.

    Therefore the main beatmap is selected using:

        LOWEST BeatmapID

    In normal osu! beatmap sets, the lowest BeatmapID is the
    first / lowest difficulty.

    Example:

        BeatmapID 100001 -> 2.31★
        BeatmapID 100002 -> 3.42★
        BeatmapID 100003 -> 5.01★

    Selected:

        BeatmapID 100001


    ============================================================
    BACKGROUND SELECTION
    ============================================================

    Only the selected lowest-BeatmapID .osu file is used for
    the normal background lookup.

    If that beatmap declares:

        0,0,"background.jpg",0,0

    then that image is used.

    If the selected beatmap's background cannot be found or
    decoded, the script DOES NOT silently switch to a higher
    BeatmapID.

    The mapset is instead recorded as "No background".


    ============================================================
    BEATMAP SET ID SELECTION
    ============================================================

    Priority:

        1. Valid BeatmapSetID from .osu
        2. Leading number from mapset folder name
        3. No SetID


    Folder examples:

        10143 IOSYS - Marisa...
        10143_IOSYS...
        10143-IOSYS...
        10143

    Invalid:

        IOSYS 10143
        Map10143
        abc10143
        123abc


    ============================================================
    OPERATIONS
    ============================================================

        1 = Create missing thumbnails only
        2 = Regenerate ALL thumbnails
        3 = Create missing / repair invalid thumbnails
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ============================================================
# CONFIGURATION
# ============================================================

$SmallWidth  = 80
$SmallHeight = 60

$LargeWidth  = 160
$LargeHeight = 120

$JpegQuality = 90


# ============================================================
# GLOBAL / RUNTIME STATE
# ============================================================

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$OsuRoot = $ScriptDirectory

$SongsDirectory = Join-Path $OsuRoot 'Songs'
$DataDirectory = Join-Path $OsuRoot 'Data'
$ThumbnailDirectory = Join-Path $DataDirectory 'bt'

$LogDirectory = Join-Path $OsuRoot 'ThumbnailGeneratorLogs'


# ============================================================
# BASIC HELPERS
# ============================================================

function Write-Header {
    param(
        [string]$Text
    )

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}


function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {

        New-Item `
            -ItemType Directory `
            -Path $Path `
            -Force |
            Out-Null
    }
}


function Add-LogLine {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    Add-Content `
        -LiteralPath $Path `
        -Value $Value `
        -Encoding UTF8
}


# ============================================================
# LOAD SYSTEM.DRAWING
# ============================================================

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


# ============================================================
# JPEG ENCODER
# ============================================================

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


function New-JpegParameters {
    param(
        [Parameter(Mandatory)]
        [int]$Quality
    )

    $parameters = New-Object `
        System.Drawing.Imaging.EncoderParameters(1)

    $qualityParameter = New-Object `
        System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [long]$Quality
        )

    $parameters.Param[0] = $qualityParameter

    return $parameters
}


# ============================================================
# IMAGE HELPERS
# ============================================================

function Test-ImageExtension {
    param(
        [Parameter(Mandatory)]
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

        default {
            return $false
        }
    }
}


function Test-ImageReadable {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $image = $null

    try {

        $image = [System.Drawing.Image]::FromFile($Path)

        return (
            $image.Width -gt 0 -and
            $image.Height -gt 0
        )
    }
    catch {

        return $false
    }
    finally {

        if ($null -ne $image) {

            try {
                $image.Dispose()
            }
            catch {
            }
        }
    }
}


function Test-Thumbnail {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$ExpectedWidth,

        [Parameter(Mandatory)]
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

        $null = $image.RawFormat

        return $true
    }
    catch {

        return $false
    }
    finally {

        if ($null -ne $image) {

            try {
                $image.Dispose()
            }
            catch {
            }
        }
    }
}


# ============================================================
# OSU FILE HELPERS
# ============================================================

function Read-OsuFileLines {
    param(
        [Parameter(Mandatory)]
        [string]$OsuFile
    )

    try {

        return [System.IO.File]::ReadAllLines(
            $OsuFile,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {

        # Fallback for unusual / legacy encoding.
        return [System.IO.File]::ReadAllLines($OsuFile)
    }
}


function Get-BeatmapId {
    param(
        [Parameter(Mandatory)]
        [string]$OsuFile
    )

    $lines = Read-OsuFileLines $OsuFile

    foreach ($line in $lines) {

        if ($line -match '^\s*BeatmapID\s*:\s*(\d+)') {

            try {
                return [int64]$Matches[1]
            }
            catch {
                return $null
            }
        }
    }

    return $null
}


function Get-BeatmapSetId {
    param(
        [Parameter(Mandatory)]
        [string]$OsuFile
    )

    $lines = Read-OsuFileLines $OsuFile

    foreach ($line in $lines) {

        if ($line -match '^\s*BeatmapSetID\s*:\s*(-?\d+)') {

            try {
                return [int64]$Matches[1]
            }
            catch {
                return $null
            }
        }
    }

    return $null
}


function Get-BackgroundReferences {
    param(
        [Parameter(Mandatory)]
        [string]$OsuFile
    )

    $results = New-Object `
        System.Collections.Generic.List[string]

    $inEvents = $false

    $lines = Read-OsuFileLines $OsuFile

    foreach ($line in $lines) {

        $trimmed = $line.Trim()

        if ($trimmed -eq '[Events]') {

            $inEvents = $true
            continue
        }

        if ($inEvents -and
            $trimmed.StartsWith('[') -and
            $trimmed.EndsWith(']')) {

            break
        }

        if (-not $inEvents) {
            continue
        }


        # Normal osu! background declaration:
        #
        # 0,0,"background.jpg",0,0
        #

        if ($trimmed -match '^\s*0\s*,\s*0\s*,\s*"([^"]+)"') {

            $filename = $Matches[1]

            if ([string]::IsNullOrWhiteSpace($filename)) {
                continue
            }


            # Ignore video backgrounds.
            if ($filename -match
                '\.(mp4|avi|webm|mov|mkv)$') {

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


function Convert-OsuRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Filename
    )

    # osu! uses forward slashes in .osu files.
    $normalized = $Filename.Replace('/', '\')

    # Remove leading path separators.
    while ($normalized.StartsWith('\')) {

        $normalized = $normalized.Substring(1)
    }

    return $normalized
}


# ============================================================
# SET ID HELPERS
# ============================================================

function Get-BeatmapSetIdFromFolderName {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$MapsetDirectory
    )

    $folderName = $MapsetDirectory.Name


    # Valid:
    #
    #   10143 IOSYS
    #   10143_IOSYS
    #   10143-IOSYS
    #   10143
    #
    # Invalid:
    #
    #   IOSYS 10143
    #   Map10143
    #   abc10143
    #   123abc
    #

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


function Get-MapsetIdInformation {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$MapsetDirectory,

        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$OsuFiles
    )

    $allIds = New-Object `
        System.Collections.Generic.List[int64]

    $validIds = New-Object `
        System.Collections.Generic.List[int64]


    # --------------------------------------------------------
    # Read BeatmapSetID from every .osu file.
    # --------------------------------------------------------

    foreach ($osuFile in $OsuFiles) {

        $id = Get-BeatmapSetId $osuFile.FullName

        if ($null -eq $id) {
            continue
        }

        $allIds.Add($id)

        # -1 means unassigned.
        if ($id -gt 0) {

            $validIds.Add($id)
        }
    }


    # --------------------------------------------------------
    # Prefer valid BeatmapSetID from .osu files.
    # --------------------------------------------------------

    if ($validIds.Count -gt 0) {

        $groups = @(
            $validIds |
                Group-Object |
                Sort-Object Count -Descending
        )

        $selectedId = [int64]$groups[0].Name

        return [PSCustomObject]@{

            SetId = $selectedId

            AllIds = $allIds

            ValidIds = $validIds

            HadMinusOne = (
                $allIds -contains [int64]-1
            )

            Conflict = ($groups.Count -gt 1)

            Source = 'OsuFile'
        }
    }


    # --------------------------------------------------------
    # No valid .osu SetID.
    #
    # Try folder name.
    # --------------------------------------------------------

    $folderId = Get-BeatmapSetIdFromFolderName `
        $MapsetDirectory

    if ($null -ne $folderId) {

        $validIds.Add($folderId)

        return [PSCustomObject]@{

            SetId = $folderId

            AllIds = $allIds

            ValidIds = $validIds

            HadMinusOne = (
                $allIds -contains [int64]-1
            )

            Conflict = $false

            Source = 'FolderName'
        }
    }


    # --------------------------------------------------------
    # Nothing found.
    # --------------------------------------------------------

    return [PSCustomObject]@{

        SetId = $null

        AllIds = $allIds

        ValidIds = $validIds

        HadMinusOne = (
            $allIds -contains [int64]-1
        )

        Conflict = $false

        Source = 'None'
    }
}


# ============================================================
# MAIN BEATMAP SELECTION
# ============================================================

function Get-MainBeatmap {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$OsuFiles
    )

    $beatmaps = New-Object `
        System.Collections.Generic.List[object]


    foreach ($osuFile in $OsuFiles) {

        $beatmapId = Get-BeatmapId $osuFile.FullName

        if ($null -eq $beatmapId) {
            continue
        }

        if ($beatmapId -le 0) {
            continue
        }

        $beatmaps.Add(
            [PSCustomObject]@{

                File = $osuFile

                BeatmapID = $beatmapId
            }
        )
    }


    if ($beatmaps.Count -eq 0) {

        return $null
    }


    # --------------------------------------------------------
    # IMPORTANT:
    #
    # Lowest BeatmapID = main / lowest difficulty.
    #
    # No Star Rating calculation is performed.
    # --------------------------------------------------------

    $sorted = @(
        $beatmaps |
            Sort-Object `
                @{ Expression = { $_.BeatmapID }; Ascending = $true },
                @{ Expression = { $_.File.Name }; Ascending = $true }
    )


    return $sorted[0]
}


# ============================================================
# BACKGROUND SELECTION
# ============================================================

function Find-MapsetBackground {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$MapsetDirectory,

        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$OsuFiles
    )


    # --------------------------------------------------------
    # FIRST:
    #
    # Select the lowest BeatmapID.
    # --------------------------------------------------------

    $mainBeatmap = Get-MainBeatmap $OsuFiles


    # --------------------------------------------------------
    # Normal path:
    #
    # A valid BeatmapID exists.
    # --------------------------------------------------------

    if ($null -ne $mainBeatmap) {

        $osuFile = $mainBeatmap.File

        $backgrounds = Get-BackgroundReferences `
            $osuFile.FullName


        foreach ($background in $backgrounds) {

            $relativePath = Convert-OsuRelativePath `
                $background

            $candidate = Join-Path `
                $MapsetDirectory.FullName `
                $relativePath


            if (-not (
                Test-Path `
                    -LiteralPath $candidate `
                    -PathType Leaf
            )) {

                continue
            }


            if (-not (Test-ImageReadable $candidate)) {

                continue
            }


            $image = $null

            try {

                $image = [System.Drawing.Image]::FromFile(
                    $candidate
                )

                return [PSCustomObject]@{

                    Path = $candidate

                    Relative = $relativePath

                    SourceOsu = $osuFile.FullName

                    BeatmapID = $mainBeatmap.BeatmapID

                    Width = $image.Width

                    Height = $image.Height
                }
            }
            finally {

                if ($null -ne $image) {

                    try {
                        $image.Dispose()
                    }
                    catch {
                    }
                }
            }
        }


        # ----------------------------------------------------
        # IMPORTANT:
        #
        # Do NOT switch to a higher BeatmapID.
        #
        # The selected lowest BeatmapID is authoritative.
        # ----------------------------------------------------

        return $null
    }


    # --------------------------------------------------------
    # Legacy / malformed fallback:
    #
    # If no BeatmapID exists anywhere, try .osu files in
    # their existing order.
    #
    # This does NOT affect normal osu!stable maps.
    # --------------------------------------------------------

    foreach ($osuFile in $OsuFiles) {

        $backgrounds = Get-BackgroundReferences `
            $osuFile.FullName


        foreach ($background in $backgrounds) {

            $relativePath = Convert-OsuRelativePath `
                $background

            $candidate = Join-Path `
                $MapsetDirectory.FullName `
                $relativePath


            if (-not (
                Test-Path `
                    -LiteralPath $candidate `
                    -PathType Leaf
            )) {

                continue
            }


            if (-not (Test-ImageReadable $candidate)) {

                continue
            }


            $image = $null

            try {

                $image = [System.Drawing.Image]::FromFile(
                    $candidate
                )

                return [PSCustomObject]@{

                    Path = $candidate

                    Relative = $relativePath

                    SourceOsu = $osuFile.FullName

                    BeatmapID = $null

                    Width = $image.Width

                    Height = $image.Height
                }
            }
            finally {

                if ($null -ne $image) {

                    try {
                        $image.Dispose()
                    }
                    catch {
                    }
                }
            }
        }
    }


    # --------------------------------------------------------
    # Final fallback:
    #
    # Search for any readable image in the mapset.
    #
    # This is only reached if no usable [Events] background
    # was found and no BeatmapID could be used.
    # --------------------------------------------------------

    try {

        $images = @(
            Get-ChildItem `
                -LiteralPath $MapsetDirectory.FullName `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    Test-ImageExtension $_.FullName
                }
        )


        foreach ($imageFile in $images) {

            if (-not (
                Test-ImageReadable $imageFile.FullName
            )) {

                continue
            }


            $image = $null

            try {

                $image = [System.Drawing.Image]::FromFile(
                    $imageFile.FullName
                )

                $relative = $imageFile.FullName.Substring(
                    $MapsetDirectory.FullName.Length
                ).TrimStart('\')


                return [PSCustomObject]@{

                    Path = $imageFile.FullName

                    Relative = $relative

                    SourceOsu = $null

                    BeatmapID = $null

                    Width = $image.Width

                    Height = $image.Height
                }
            }
            finally {

                if ($null -ne $image) {

                    try {
                        $image.Dispose()
                    }
                    catch {
                    }
                }
            }
        }
    }
    catch {
    }


    return $null
}


# ============================================================
# THUMBNAIL GENERATION
# ============================================================

function New-ThumbnailImage {
    param(
        [Parameter(Mandatory)]
        [System.Drawing.Image]$SourceImage,

        [Parameter(Mandatory)]
        [int]$TargetWidth,

        [Parameter(Mandatory)]
        [int]$TargetHeight
    )

    $sourceWidth = $SourceImage.Width
    $sourceHeight = $SourceImage.Height


    if ($sourceWidth -le 0 -or
        $sourceHeight -le 0) {

        throw "Invalid source image dimensions."
    }


    $sourceAspect =
        $sourceWidth / [double]$sourceHeight

    $targetAspect =
        $TargetWidth / [double]$TargetHeight


    [int]$cropX = 0
    [int]$cropY = 0
    [int]$cropWidth = $sourceWidth
    [int]$cropHeight = $sourceHeight


    # --------------------------------------------------------
    # Crop horizontally.
    # --------------------------------------------------------

    if ($sourceAspect -gt $targetAspect) {

        $cropWidth = [int][Math]::Round(
            $sourceHeight * $targetAspect
        )

        $cropX = [int][Math]::Round(
            ($sourceWidth - $cropWidth) / 2.0
        )
    }


    # --------------------------------------------------------
    # Crop vertically.
    # --------------------------------------------------------

    elseif ($sourceAspect -lt $targetAspect) {

        $cropHeight = [int][Math]::Round(
            $sourceWidth / $targetAspect
        )

        $cropY = [int][Math]::Round(
            ($sourceHeight - $cropHeight) / 2.0
        )
    }


    $bitmap = New-Object `
        System.Drawing.Bitmap(
            $TargetWidth,
            $TargetHeight,
            [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
        )


    $graphics = [System.Drawing.Graphics]::FromImage(
        $bitmap
    )


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


        $destinationRectangle =
            [System.Drawing.Rectangle]::new(
                0,
                0,
                $TargetWidth,
                $TargetHeight
            )


        $graphics.DrawImage(
            $SourceImage,
            $destinationRectangle,
            $cropX,
            $cropY,
            $cropWidth,
            $cropHeight,
            [System.Drawing.GraphicsUnit]::Pixel
        )
    }
    catch {

        $bitmap.Dispose()

        throw
    }
    finally {

        $graphics.Dispose()
    }


    return $bitmap
}


# ============================================================
# JPEG OUTPUT
# ============================================================

function Save-JpegAtomic {
    param(
        [Parameter(Mandatory)]
        [System.Drawing.Bitmap]$Bitmap,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [int]$Quality
    )


    $directory = Split-Path `
        -Parent `
        $OutputPath


    Ensure-Directory $directory


    $temporaryPath = $OutputPath + '.tmp'


    if (Test-Path -LiteralPath $temporaryPath) {

        try {

            Remove-Item `
                -LiteralPath $temporaryPath `
                -Force
        }
        catch {
        }
    }


    $encoderParameters = $null


    try {

        $encoderParameters = New-JpegParameters `
            $Quality


        $Bitmap.Save(
            $temporaryPath,
            $JpegCodec,
            $encoderParameters
        )


        if (-not (
            Test-Path `
                -LiteralPath $temporaryPath `
                -PathType Leaf
        )) {

            throw "Temporary JPEG was not created."
        }


        if (Test-Path `
            -LiteralPath $OutputPath `
            -PathType Leaf) {

            Remove-Item `
                -LiteralPath $OutputPath `
                -Force
        }


        Move-Item `
            -LiteralPath $temporaryPath `
            -Destination $OutputPath `
            -Force
    }
    finally {

        if ($null -ne $encoderParameters) {

            try {
                $encoderParameters.Dispose()
            }
            catch {
            }
        }


        if (Test-Path `
            -LiteralPath $temporaryPath `
            -PathType Leaf) {

            try {

                Remove-Item `
                    -LiteralPath $temporaryPath `
                    -Force
            }
            catch {
            }
        }
    }
}


# ============================================================
# OPERATION SELECTION
# ============================================================

Write-Header "osu! Thumbnail Cache Generator"

Write-Host "osu! root:"
Write-Host "  $OsuRoot"
Write-Host ""

Write-Host "Songs:"
Write-Host "  $SongsDirectory"
Write-Host ""

Write-Host "Thumbnail cache:"
Write-Host "  $ThumbnailDirectory"
Write-Host ""

Write-Host "Main beatmap selection:"
Write-Host "  Lowest BeatmapID"
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


# ============================================================
# VERIFY DIRECTORIES
# ============================================================

if (-not (
    Test-Path `
        -LiteralPath $SongsDirectory `
        -PathType Container
)) {

    Write-Host ""
    Write-Host "Songs folder was not found:" -ForegroundColor Red
    Write-Host "  $SongsDirectory"
    Write-Host ""

    Write-Host "The script should normally be placed here:" `
        -ForegroundColor Yellow

    Write-Host "  C:\osu!\GenerateOsuThumbnails.ps1"
    Write-Host ""

    exit 1
}


Ensure-Directory $ThumbnailDirectory
Ensure-Directory $LogDirectory


# ============================================================
# LOG FILES
# ============================================================

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


$SelectedBeatmapLog = Join-Path `
    $LogDirectory `
    "selected_beatmaps_$timestamp.txt"


# ============================================================
# STATISTICS
# ============================================================

$Stats = [ordered]@{

    MapsetsScanned = 0

    BeatmapsScanned = 0

    Created = 0

    Skipped = 0

    Repaired = 0

    MinusOneFixed = 0

    FolderNameIds = 0

    SetIdConflicts = 0

    NoBackground = 0

    NoSetId = 0

    Failed = 0
}


$StartTime = Get-Date


# ============================================================
# SCAN SONGS
# ============================================================

Write-Host ""
Write-Host "Scanning Songs..." -ForegroundColor Cyan
Write-Host ""


$mapsetDirectories = @(
    Get-ChildItem `
        -LiteralPath $SongsDirectory `
        -Directory `
        -Recurse `
        -ErrorAction SilentlyContinue
)


$totalDirectories = $mapsetDirectories.Count

$currentDirectoryIndex = 0


# ============================================================
# PROCESS MAPSETS
# ============================================================

foreach ($mapsetDirectory in $mapsetDirectories) {

    $currentDirectoryIndex++


    # --------------------------------------------------------
    # Find .osu files directly inside this directory.
    # --------------------------------------------------------

    $osuFiles = @(
        Get-ChildItem `
            -LiteralPath $mapsetDirectory.FullName `
            -Filter '*.osu' `
            -File `
            -ErrorAction SilentlyContinue
    )


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

        $percent = [int][Math]::Min(
            100,
            (
                $currentDirectoryIndex /
                [double]$totalDirectories
            ) * 100
        )
    }


    Write-Progress `
        -Activity "Generating osu! thumbnails" `
        -Status "$currentDirectoryIndex / $totalDirectories : $($mapsetDirectory.Name)" `
        -PercentComplete $percent


    try {

        # ====================================================
        # DETERMINE BEATMAP SET ID
        # ====================================================

        $idInfo = Get-MapsetIdInformation `
            $mapsetDirectory `
            $osuFiles


        $setId = $idInfo.SetId


        if ($null -eq $setId) {

            $Stats.NoSetId++


            Add-LogLine `
                $FailedLog `
                "NO SETID: $($mapsetDirectory.FullName)"


            continue
        }


        # ----------------------------------------------------
        # Folder-name fallback
        # ----------------------------------------------------

        if ($idInfo.Source -eq 'FolderName') {

            $Stats.FolderNameIds++


            Add-LogLine `
                $FolderIdLog `
                "$setId`t$($mapsetDirectory.FullName)"
        }


        # ----------------------------------------------------
        # -1 SetID
        # ----------------------------------------------------

        if ($idInfo.HadMinusOne) {

            $Stats.MinusOneFixed++


            Add-LogLine `
                $MinusOneLog `
                "$setId`t$($mapsetDirectory.FullName)"
        }


        # ----------------------------------------------------
        # SetID conflicts
        # ----------------------------------------------------

        if ($idInfo.Conflict) {

            $Stats.SetIdConflicts++


            $idsString = (
                $idInfo.ValidIds |
                    Sort-Object -Unique
            ) -join ', '


            Add-LogLine `
                $ConflictLog `
                "SELECTED=$setId`tIDS=$idsString`tPATH=$($mapsetDirectory.FullName)"
        }


        # ====================================================
        # OUTPUT PATHS
        # ====================================================

        $smallOutput = Join-Path `
            $ThumbnailDirectory `
            "$setId.jpg"


        $largeOutput = Join-Path `
            $ThumbnailDirectory `
            "${setId}l.jpg"


        # ====================================================
        # CHECK EXISTING CACHE
        # ====================================================

        $smallValid = Test-Thumbnail `
            $smallOutput `
            $SmallWidth `
            $SmallHeight


        $largeValid = Test-Thumbnail `
            $largeOutput `
            $LargeWidth `
            $LargeHeight


        # ----------------------------------------------------
        # Missing / Repair:
        #
        # If both files are already valid, nothing to do.
        # ----------------------------------------------------

        if (
            ($Operation -eq 'Missing' -or
             $Operation -eq 'Repair') -and
            $smallValid -and
            $largeValid
        ) {

            $Stats.Skipped++

            continue
        }


        # ====================================================
        # SELECT MAIN BEATMAP
        # ====================================================

        $mainBeatmap = Get-MainBeatmap $osuFiles


        if ($null -ne $mainBeatmap) {

            Add-LogLine `
                $SelectedBeatmapLog `
                "SETID=$setId`tBEATMAPID=$($mainBeatmap.BeatmapID)`tOSU=$($mainBeatmap.File.Name)`tPATH=$($mapsetDirectory.FullName)"
        }
        else {

            Add-LogLine `
                $SelectedBeatmapLog `
                "SETID=$setId`tBEATMAPID=NONE`tOSU=NONE`tPATH=$($mapsetDirectory.FullName)"
        }


        # ====================================================
        # FIND BACKGROUND
        # ====================================================

        $background = Find-MapsetBackground `
            $mapsetDirectory `
            $osuFiles


        if ($null -eq $background) {

            $Stats.NoBackground++


            Add-LogLine `
                $NoBackgroundLog `
                "SETID=$setId`tPATH=$($mapsetDirectory.FullName)"


            continue
        }


        # ====================================================
        # LOAD SOURCE IMAGE
        # ====================================================

        $sourceImage = $null

        $smallBitmap = $null

        $largeBitmap = $null


        try {

            $sourceImage = [System.Drawing.Image]::FromFile(
                $background.Path
            )


            # =================================================
            # GENERATE LARGE THUMBNAIL
            # =================================================

            $largeBitmap = New-ThumbnailImage `
                $sourceImage `
                $LargeWidth `
                $LargeHeight


            # =================================================
            # GENERATE SMALL THUMBNAIL
            # =================================================

            $smallBitmap = New-ThumbnailImage `
                $sourceImage `
                $SmallWidth `
                $SmallHeight


            # =================================================
            # DETERMINE WHAT TO WRITE
            # =================================================

            $shouldWriteSmall = $true

            $shouldWriteLarge = $true


            if (
                $Operation -eq 'Missing' -or
                $Operation -eq 'Repair'
            ) {

                if ($smallValid) {

                    $shouldWriteSmall = $false
                }


                if ($largeValid) {

                    $shouldWriteLarge = $false
                }
            }


            # =================================================
            # WRITE LARGE
            # =================================================

            if ($shouldWriteLarge) {

                Save-JpegAtomic `
                    $largeBitmap `
                    $largeOutput `
                    $JpegQuality
            }


            # =================================================
            # WRITE SMALL
            # =================================================

            if ($shouldWriteSmall) {

                Save-JpegAtomic `
                    $smallBitmap `
                    $smallOutput `
                    $JpegQuality
            }


            # =================================================
            # VERIFY OUTPUT
            # =================================================

            $verifiedSmall = Test-Thumbnail `
                $smallOutput `
                $SmallWidth `
                $SmallHeight


            $verifiedLarge = Test-Thumbnail `
                $largeOutput `
                $LargeWidth `
                $LargeHeight


            if (-not $verifiedSmall) {

                throw `
                    "Generated small thumbnail failed verification."
            }


            if (-not $verifiedLarge) {

                throw `
                    "Generated large thumbnail failed verification."
            }


            # =================================================
            # STATISTICS
            # =================================================

            if (
                $Operation -eq 'Repair' -and
                (
                    -not $smallValid -or
                    -not $largeValid
                )
            ) {

                $Stats.Repaired++
            }
            else {

                $Stats.Created++
            }
        }
        catch {

            $Stats.Failed++


            Add-LogLine `
                $FailedLog `
                "FAILED: $($mapsetDirectory.FullName)"


            Add-LogLine `
                $FailedLog `
                "  SetID: $setId"


            Add-LogLine `
                $FailedLog `
                "  SetID source: $($idInfo.Source)"


            if ($null -ne $mainBeatmap) {

                Add-LogLine `
                    $FailedLog `
                    "  Main BeatmapID: $($mainBeatmap.BeatmapID)"

                Add-LogLine `
                    $FailedLog `
                    "  Main .osu: $($mainBeatmap.File.FullName)"
            }


            Add-LogLine `
                $FailedLog `
                "  Background: $($background.Path)"


            Add-LogLine `
                $FailedLog `
                "  Error: $($_.Exception.Message)"


            Add-LogLine `
                $FailedLog `
                ""
        }
        finally {

            # ------------------------------------------------
            # Dispose small bitmap.
            # ------------------------------------------------

            if ($null -ne $smallBitmap) {

                try {
                    $smallBitmap.Dispose()
                }
                catch {
                }
            }


            # ------------------------------------------------
            # Dispose large bitmap.
            # ------------------------------------------------

            if ($null -ne $largeBitmap) {

                try {
                    $largeBitmap.Dispose()
                }
                catch {
                }
            }


            # ------------------------------------------------
            # Dispose source image.
            # ------------------------------------------------

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


        Add-LogLine `
            $FailedLog `
            "FAILED MAPSET: $($mapsetDirectory.FullName)"


        Add-LogLine `
            $FailedLog `
            "ERROR: $($_.Exception.Message)"


        Add-LogLine `
            $FailedLog `
            ""
    }
}


# ============================================================
# FINISH PROGRESS
# ============================================================

Write-Progress `
    -Activity "Generating osu! thumbnails" `
    -Completed


# ============================================================
# FINAL STATISTICS
# ============================================================

$EndTime = Get-Date

$Elapsed = $EndTime - $StartTime


Write-Header "COMPLETE"


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


# ============================================================
# SUMMARY LOG
# ============================================================

$summaryFile = Join-Path `
    $LogDirectory `
    "summary_$timestamp.txt"


$summary = @"
osu! Thumbnail Cache Generator
==============================

Main Beatmap Selection:
Lowest BeatmapID

Star Rating:
Not read / not calculated

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

Failed log:
$FailedLog

Minus-one log:
$MinusOneLog

SetID conflict log:
$ConflictLog

No-background log:
$NoBackgroundLog

Folder-name SetID log:
$FolderIdLog

Selected Beatmap log:
$SelectedBeatmapLog
"@


Set-Content `
    -LiteralPath $summaryFile `
    -Value $summary `
    -Encoding UTF8


Write-Host "Summary saved to:"
Write-Host "  $summaryFile"

Write-Host ""


# ============================================================
# WARNINGS
# ============================================================

if ($Stats.Failed -gt 0) {

    Write-Host "There were errors." -ForegroundColor Yellow

    Write-Host "Check:"
    Write-Host "  $FailedLog"

    Write-Host ""
}


if ($Stats.NoSetId -gt 0) {

    Write-Host `
        "Some mapsets had no valid BeatmapSetID." `
        -ForegroundColor Yellow

    Write-Host `
        "These cannot safely be written to Data\bt."

    Write-Host ""
}


if ($Stats.NoBackground -gt 0) {

    Write-Host `
        "Some mapsets had no usable background on their lowest BeatmapID." `
        -ForegroundColor Yellow

    Write-Host "Check:"
    Write-Host "  $NoBackgroundLog"

    Write-Host ""
}


if ($Stats.FolderNameIds -gt 0) {

    Write-Host `
        "Some SetIDs were recovered from folder names." `
        -ForegroundColor Green

    Write-Host "Check:"
    Write-Host "  $FolderIdLog"

    Write-Host ""
}


Write-Host "Done." -ForegroundColor Green
