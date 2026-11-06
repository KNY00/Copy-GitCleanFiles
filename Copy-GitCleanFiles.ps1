<#
.SYNOPSIS
    Copies all non-gitignored files from a source Git directory to a destination directory.
.DESCRIPTION
    Queries Git for all tracked and untracked files that are not ignored by standard
    gitignore rules (plus any custom exclusions), and copies them to a clean destination
    directory while preserving the folder hierarchy.
.PARAMETER Source
    The source folder path (must be inside a Git work tree).
.PARAMETER Destination
    The destination folder path.
.PARAMETER Exclude
    Additional file or folder glob patterns to exclude from the copy operation.
.PARAMETER Force
    Bypasses the interactive 'confirm destruction' prompt when overwriting an existing destination.
.EXAMPLE
    .\Copy-GitCleanFiles.ps1 -Source ./my-repo -Destination /tmp/backup
    .\Copy-GitCleanFiles.ps1 -s . -d ../output -Exclude "*.lock", "docs/**" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Source folder path.")]
    [Alias("s", "Src")]
    [string]$Source,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Destination folder path.")]
    [Alias("d", "Dest")]
    [string]$Destination,

    [Parameter(Mandatory = $false, HelpMessage = "Additional file or folder glob patterns to exclude.")]
    [Alias("e", "Excl")]
    [string[]]$Exclude = @(),

    [Parameter(HelpMessage = "Bypass interactive destruction confirmation.")]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Resolve-NormalizedPath {
    param ([string]$InputPath)

    # Resolve path against PowerShell's current working directory ($PWD) even if the path does not exist yet
    $FullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputPath)

    # Preserve root separator (e.g. 'C:\' or '/') while stripping trailing slashes on subfolders
    $Root = [System.IO.Path]::GetPathRoot($FullPath)
    if ($FullPath -eq $Root) {
        return $FullPath
    }

    return $FullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathRelationship {
    param (
        [string]$SourcePath,
        [string]$DestPath
    )

    # Normalize slashes and split into path segments
    $SegmentsSrc  = ($SourcePath -replace '\\', '/').Trim('/') -split '/'
    $SegmentsDest = ($DestPath -replace '\\', '/').Trim('/') -split '/'

    # Check OS platform: Windows file systems are case-insensitive; Linux/macOS are case-sensitive
    $IsWindowsOS = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
    $StringComparison = if ($IsWindowsOS) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    $MinCount = [Math]::Min($SegmentsSrc.Count, $SegmentsDest.Count)
    for ($i = 0; $i -lt $MinCount; $i++) {
        if (-not [string]::Equals($SegmentsSrc[$i], $SegmentsDest[$i], $StringComparison)) {
            return 'Unrelated'
        }
    }

    if ($SegmentsSrc.Count -eq $SegmentsDest.Count) { return 'Same' }
    if ($SegmentsDest.Count -gt $SegmentsSrc.Count) { return 'DestInsideSource' }
    return 'SourceInsideDest'
}

# 0. Verify Git CLI is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git executable not found in PATH. Please install Git before running this script."
}

# 1. Resolve and validate Source path
$ResolvedSource = Resolve-NormalizedPath -InputPath $Source
if (-not (Test-Path -LiteralPath $ResolvedSource -PathType Container)) {
    throw "Source directory does not exist or is a file: '$ResolvedSource'"
}

# 2. Resolve Destination path and validate hierarchy relationship
$ResolvedDestination = Resolve-NormalizedPath -InputPath $Destination
$PathRelation = Test-PathRelationship -SourcePath $ResolvedSource -DestPath $ResolvedDestination

switch ($PathRelation) {
    'Same' {
        throw "You are trying to duplicate the source folder into itself (NOT ALLOWED): '$ResolvedSource'"
    }
    'SourceInsideDest' {
        throw "Destination folder '$ResolvedDestination' is a parent of Source '$ResolvedSource'. Aborting to prevent deleting the source repository."
    }
    'DestInsideSource' {
        throw "Destination folder '$ResolvedDestination' cannot be nested inside Source '$ResolvedSource'."
    }
}

# 3. Query Git for non-ignored files BEFORE modifying the destination on disk
Push-Location -LiteralPath $ResolvedSource
try {
    # Set console output encoding to UTF-8 so non-ASCII filenames read cleanly
    $OriginalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Base arguments to fetch tracked and untracked files excluding standard .gitignore rules
    # (-c core.quotepath=false prevents octal escaping)
    $GitArgs = @(
        '-c', 'core.quotepath=false',
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard'
    )

    # Append custom pathspec exclusions if -Exclude is provided
    if ($Exclude.Count -gt 0) {
        $GitArgs += '--'
        $GitArgs += '.'
        foreach ($Pattern in $Exclude) {
            if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
                # Normalize backslashes to forward slashes for Git pathspecs
                $CleanPattern = $Pattern.Trim() -replace '\\', '/'
                # Use :(exclude,glob) so glob patterns work across both tracked and untracked files
                $GitArgs += ":(exclude,glob)$CleanPattern"
            }
        }
    }

    $FilesToCopy = @(git @GitArgs)

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to execute 'git ls-files'. Ensure '$ResolvedSource' is a valid Git repository."
    }
}
finally {
    [Console]::OutputEncoding = $OriginalEncoding
    Pop-Location
}

# 4. Validate Destination as a folder, handle destruction confirmation, or create it
if (Test-Path -LiteralPath $ResolvedDestination) {
    if (Test-Path -LiteralPath $ResolvedDestination -PathType Leaf) {
        throw "Destination path points to an existing file, not a folder: '$ResolvedDestination'"
    }

    if (-not $Force -and -not $WhatIfPreference) {
        Write-Warning "Destination folder already exists: '$ResolvedDestination'"
        $Confirmation = Read-Host "Type 'confirm destruction' to destroy it and continue"

        if ($Confirmation -cne "confirm destruction") {
            throw "Operation aborted by user. Confirmation phrase did not match 'confirm destruction'."
        }
    }

    if ($PSCmdlet.ShouldProcess($ResolvedDestination, "Remove existing destination directory")) {
        Write-Host "Removing existing destination folder..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $ResolvedDestination -Recurse -Force
    }
}

if ($PSCmdlet.ShouldProcess($ResolvedDestination, "Create clean destination directory")) {
    New-Item -ItemType Directory -Path $ResolvedDestination -Force | Out-Null
}

# 5. Copy files to destination
$CopiedCount = 0

foreach ($RelativeFile in $FilesToCopy) {
    if ([string]::IsNullOrWhiteSpace($RelativeFile)) { continue }

    $SourceFilePath = Join-Path -Path $ResolvedSource -ChildPath $RelativeFile
    $DestFilePath   = Join-Path -Path $ResolvedDestination -ChildPath $RelativeFile

    # Skip if a tracked file was deleted locally from disk (or is a submodule directory)
    if (-not (Test-Path -LiteralPath $SourceFilePath -PathType Leaf)) {
        continue
    }

    if ($PSCmdlet.ShouldProcess($DestFilePath, "Copy from '$RelativeFile'")) {
        # Ensure parent subdirectories exist in the destination
        $DestParentDir = [System.IO.Path]::GetDirectoryName($DestFilePath)
        if (-not (Test-Path -LiteralPath $DestParentDir -PathType Container)) {
            New-Item -ItemType Directory -Path $DestParentDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $SourceFilePath -Destination $DestFilePath -Force
    }
    $CopiedCount++
}

Write-Host "Successfully copied $CopiedCount files to '$ResolvedDestination'." -ForegroundColor Green