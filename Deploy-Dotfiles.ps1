<#
.SYNOPSIS
    Deploy dotfiles by creating matching destination folders and symbolic links for files.
.DESCRIPTION
    This script takes a dotfiles folder, a destination folder, and several switches:
      -DryRun: simulate the changes without modifying the system.
      -VerboseOutput: print extra logging details.
      -AutoApprove: automatically move existing destination files into the dotfiles folder.

    It:
      1. Validates that both folders exist.
      2. Collects ignore rules (the script file itself is ignored, and if a file named .dotfile-ignore exists, it is parsed similarly to a .gitignore).
      3. Mirrors the folder structure from the dotfiles folder into the destination.
      4. Processes every file (skipping ignored ones and itself): if a corresponding file exists at the destination, it asks (or auto-approves) to move that file back into the dotfiles folder.
      5. Creates a symbolic link in the destination folder for each file.

.PARAMETER DotfilesFolder
    Path to the dotfiles folder. Defaults to the current directory.

.PARAMETER DestinationFolder
    The destination directory where symlinks will be created. Defaults to $env:USERPROFILE.

.PARAMETER DryRun
    If set, no real changes are made.

.PARAMETER VerboseOutput
    If set, additional informational output is shown.

.PARAMETER AutoApprove
    If set, existing destination files are automatically moved without prompting.
#>

[CmdletBinding()]
param (
    [string]$DotfilesFolder = (Get-Location).Path,
    [string]$DestinationFolder = $env:USERPROFILE,
    [switch]$DryRun,
    [switch]$VerboseOutput,
    [switch]$AutoApprove
)

# Convert to full paths to ensure proper substring operations
$DotfilesFolder = (Resolve-Path $DotfilesFolder).Path
$DestinationFolder = (Resolve-Path $DestinationFolder).Path

# Prepare the list of ignore patterns.
$IgnoredPaths = @()
$DotfileIgnoreListFileName = ".dotfile-ignore"
$DotfileIgnoreListFilePath = Join-Path $DotfilesFolder $DotfileIgnoreListFileName


# ==============================================================================
# Func: Writes messages when VerboseOutput is enabled.
# ==============================================================================

function Write-VerboseCustom {
    param ([string]$Message)
    if ($VerboseOutput) {
        Write-Host "$Message"
    }
}


# ==============================================================================
# Func: Validate a .gitignore‑style path.
# ==============================================================================

function IsValidGitIgnorePath {
    param (
        [string]$Pattern
    )
    $trimmedPattern = $Pattern.Trim()
    # Reject empty strings (should have been filtered) and any that contain ':' (to avoid drive letters).
    if ([string]::IsNullOrEmpty($trimmedPattern) -or $trimmedPattern.Contains(":")) {
        return $false
    }
    # Allow an optional '!' negation at the beginning, and then only allow alphanumerics, underscore, dash, dot, asterisk, slash.
    if ($trimmedPattern -match '^(?:!?)[\w\-\.\*\/]+\/?$') {
        return $true
    }
    return $false
}


# Output Dry Run header if in DryRun mode.
if ($DryRun) {
    Write-Host "==============================================================================="
    Write-Host "==                                  DRY RUN                                  =="
    Write-Host "==============================================================================="
}

# Validate that both the dotfiles and destination directories exist.
if (-not (Test-Path -Path $DotfilesFolder -PathType Container)) {
    Write-Error "Dotfiles folder '$DotfilesFolder' does not exist."
    exit 1
}
if (-not (Test-Path -Path $DestinationFolder -PathType Container)) {
    Write-Error "Destination folder '$DestinationFolder' does not exist."
    exit 1
}

Write-VerboseCustom "Matching Folder Structure"
Write-VerboseCustom "     Dot Folder: $DotfilesFolder"
Write-VerboseCustom "    Real Folder: $DestinationFolder"
Write-Output ""

# ==============================================================================
# Process .dotfile-ignore
# ==============================================================================

# If not in DryRun mode, ensure admin privileges for symbolic link creation.
if (-not $DryRun) {
    function Test-Admin {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    if (-not (Test-Admin)) {
        Write-VerboseCustom "Symbolic Link creation requires Admin permission"
        Write-VerboseCustom "- Checking for Existing Admin Permissions..."
        Write-Host "Admin Permissions are required. Restarting script with elevated privileges..."
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $arguments += " -DotfilesFolder `"$DotfilesFolder`" -DestinationFolder `"$DestinationFolder`""
        if ($DryRun) { $arguments += " -DryRun" }
        if ($VerboseOutput) { $arguments += " -VerboseOutput" }
        if ($AutoApprove) { $arguments += " -AutoApprove" }
        Start-Process powershell -Verb runAs -ArgumentList $arguments
        exit
    }
    else {
        Write-VerboseCustom "- Admin Permissions Obtained."
    }
}
else {
    Write-Output "Skipping Admin Permissions, Dry Run mode is enabled."
}

Write-Output ""


# Determine the full path of the running script.
$ScriptPath = $MyInvocation.MyCommand.Path

# Check for the .dotfile-ignore file.
Write-VerboseCustom "Searching for $DotfileIgnoreListFileName"
if (Test-Path $DotfileIgnoreListFilePath) {
    Write-VerboseCustom "Found $DotfileIgnoreListFileName"
    Write-VerboseCustom "Reading contents $DotfileIgnoreListFileName"
    $ignoreLines = Get-Content $DotfileIgnoreListFilePath | ForEach-Object { $_.Trim() } | Where-Object { ($_ -ne "") -and (-not $_.StartsWith("#")) }
    foreach ($line in $ignoreLines) {
        if (IsValidGitIgnorePath $line) {
            $IgnoredPaths += $line
            Write-VerboseCustom "    $line"
        }
        else {
            Write-VerboseCustom "    $line (skipped: invalid .gitignore pattern)"
        }
    }
}

# Helper Function: Determines if a relative path should be ignored.
function IsIgnored {
    param (
        [string]$RelativePath
    )
    foreach ($pattern in $IgnoredPaths) {
        # Use -like for wildcard matching or direct start comparison.
        if ($RelativePath -like $pattern -or $RelativePath.StartsWith($pattern)) {
            return $true
        }
    }
    return $false
}

# Counters for summary
$CreatedFolderCount = 0
$CreatedLinkCount = 0

# ==============================================================================
# Folders
# ==============================================================================

Write-Output ""
Write-Output "Processing Folders in: $DotfilesFolder"
Write-Output ""

$Directories = Get-ChildItem -Path $DotfilesFolder -Directory -Recurse | Sort-Object { $_.FullName }

foreach ($dir in $Directories) {
    # Write-Output "$dir"

    # Get the relative path by removing the dotfiles folder root portion.
    $relativeDir = $dir.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')

    # Calculate Destination Dir
    $destDir = Join-Path $DestinationFolder $relativeDir

    # Write-Output "$relativeDir"
    if (IsIgnored $relativeDir) {
        Write-Output "Ignored:  $destDir"
        continue
    }
    if (-not (Test-Path $destDir -PathType Container)) {
        Write-Output "Creating: $destDir"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $destDir | Out-Null
        }
        $CreatedFolderCount++
    }
    else {
        Write-Output "Exists:   $destDir"
    }
}



# ==============================================================================
# Files
# ==============================================================================

Write-Output ""
Write-Output "Processing Files in: $DotfilesFolder"
Write-Output ""

$Files = Get-ChildItem -Path $DotfilesFolder -File -Recurse | Sort-Object { $_.FullName }

foreach ($file in $Files) {
    $relativeFile = $file.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')
    $destinationFile = Join-Path $DestinationFolder $relativeFile

    # Skip processing if the current file is the running script itself.
    if ($file.FullName -eq $ScriptPath) {
        Write-Output "Skip:        $destinationFile"
        continue
    }
    if (IsIgnored $relativeFile) {
        Write-Output "Ignored:     $destinationFile"
        continue
    }

    # If the destination file already exists, first check if it is a symbolic link
    # that correctly points to the source file.
    if (Test-Path $destinationFile) {
        $destItem = Get-Item $destinationFile -Force
        if ( ($destItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and ($destItem.Target -eq $file.FullName) ) {
            Write-Output "Exists:      $destinationFile"
            continue
        }

        Write-Output "Adopt?:      $destinationFile"
        $moveFile = $false
        if ($AutoApprove) {
            $moveFile = $true
            Write-VerboseCustom "+ AutoApprove adopting file"
        }
        else {
            Write-Output "+ File $destinationFile exists."
            $response = Read-Host "? Do you want to move it to the dotfiles folder? (Y/N)"
            if ($response -match '^(Y|y)') {
                $moveFile = $true
            }
        }
        if ($moveFile) {
            Write-VerboseCustom "+ Moving file $destinationFile to $($file.FullName)"
            if (-not $DryRun) {
                # Move the existing destination file, which overwrites the file in the dotfiles folder.
                Move-Item -Path $destinationFile -Destination $file.FullName -Force
            }
        }
        else {
            Write-VerboseCustom "+ Not moving file $destinationFile"
            continue
        }
    }

    # Create the symbolic link only if the destination file does not already exist.
    if (Test-Path $destinationFile) {
        Write-Output "Exists:      $destinationFile"
        continue
    }

    Write-Output "Creating:    $destinationFile -> $($file.FullName)"
    if (-not $DryRun) {
        New-Item -ItemType SymbolicLink -Path $destinationFile -Target $file.FullName | Out-Null
    }
    $CreatedLinkCount++
}

# ==============================================================================
# Final summary output.
# ==============================================================================

Write-Host ""
if ($DryRun) {
    Write-Host "Dry Run Mode Enabled."
    Write-Host "Would have Created $CreatedFolderCount Folders"
    Write-Host "Would have Created $CreatedLinkCount Symbolic Links"
}
else {
    Write-Host "Created $CreatedFolderCount Folders"
    Write-Host "Created $CreatedLinkCount Symbolic Links"
}
