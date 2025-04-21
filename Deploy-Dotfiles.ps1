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
      5. Queues symbolic link creation for each file.
      6. At the end, if not in DryRun mode, it ensures that the current PowerShell version is 7 or later and then combines all symbolic link commands into a single chain using "&&". If not elevated, it launches an elevated process to execute the chain.

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

# Ensure the PowerShell version is 7 or later for "&&" support.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later for the symbolic link command chaining. Please upgrade and try again."
    exit 1
}

# Convert to full paths to ensure proper substring operations.
$DotfilesFolder = (Resolve-Path $DotfilesFolder).Path
$DestinationFolder = (Resolve-Path $DestinationFolder).Path

# Define a helper function to check for admin privileges.
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Prepare the list of ignore patterns.
$DotfileIgnoreListFileName = ".dotfile-ignore"
$DotfileIgnoreListFilePath = Join-Path $DotfilesFolder $DotfileIgnoreListFileName
$IgnoredPaths = @( $DotfileIgnoreListFileName )
$ScriptPath = $MyInvocation.MyCommand.Path

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
    # Reject empty strings and any that contain ':' (to avoid drive letters).
    if ([string]::IsNullOrEmpty($trimmedPattern) -or $trimmedPattern.Contains(":")) {
        return $false
    }
    # Allow an optional '!' negation at the beginning, then only allow alphanumerics, underscore, dash, dot, asterisk, slash.
    if ($trimmedPattern -match '^(?:!?)[\w\-\.\*\/]+\/?$') {
        return $true
    }
    return $false
}

# ==============================================================================
# Func: Determines if a relative path should be ignored.
# ==============================================================================

function IsIgnored {
    param (
        [string]$RelativePath
    )
    foreach ($pattern in $IgnoredPaths) {
        if ($RelativePath -like $pattern -or $RelativePath.StartsWith($pattern)) {
            return $true
        }
    }
    return $false
}

# ==============================================================================
# Func: Determines if a relative path should be ignored.
# ==============================================================================

function Write-Path {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [int]$Pad = 16,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [bool]$VerboseOnly = $false,

        [string]$Link_Path
    )

    if ($VerboseOnly -and -not $VerboseOutput) {
        return
    }

    $Status = "${Status}:"

    $PaddedStatus = $Status.PadRight($Pad)
    Write-Host "${PaddedStatus} $Path"

    if ($Link_Path) {
        $LinkPadding = ' ' * ($Pad + 1)
        Write-Host "$LinkPadding-> $Link_Path"
    }
}

# ==============================================================================
# Early Validations
# ==============================================================================

if ($DryRun) {
    Write-Host "==============================================================================="
    Write-Host "==                                  DRY RUN                                  =="
    Write-Host "==============================================================================="
}

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

Write-VerboseCustom "Searching for $DotfileIgnoreListFileName"
if (Test-Path $DotfileIgnoreListFilePath) {
    Write-VerboseCustom "Found $DotfileIgnoreListFileName"
    Write-VerboseCustom "Reading contents $DotfileIgnoreListFileName"
    $ignoreLines = Get-Content $DotfileIgnoreListFilePath | ForEach-Object { $_.Trim() } |
    Where-Object { ($_ -ne "") -and (-not $_.StartsWith("#")) }
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

# ==============================================================================
# Folders Creation
# ==============================================================================

$CreatedFolderCount = 0
$CreatedLinkCount = 0

Write-Output ""
Write-Output "Processing Folders in: $DotfilesFolder"
Write-Output ""

$Directories = Get-ChildItem -Path $DotfilesFolder -Directory -Recurse | Sort-Object { $_.FullName }
foreach ($dir in $Directories) {
    $relativeDir = $dir.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')
    $destDir = Join-Path $DestinationFolder $relativeDir

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
# Files Processing and Queuing Symlink Creation
# ==============================================================================

# Array to collect symbolic link creation commands.
$SymlinkCommands = @()

Write-Output ""
Write-Output "Processing Files in: $DotfilesFolder"
Write-Output ""

$Files = Get-ChildItem -Path $DotfilesFolder -File -Recurse | Sort-Object { $_.FullName }
foreach ($file in $Files) {
    $relativeFile = $file.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')
    $destinationFile = Join-Path $DestinationFolder $relativeFile

    # Its this script, or its on the Skip List
    if ( ($file.FullName -eq $ScriptPath) -or (IsIgnored $relativeFile) ) {
        Write-Path -Status "Ignored" -Path $destinationFile
        continue
    }

    # Does the Symbolic Link already exist?
    if (Test-Path $destinationFile) {
        $destItem = Get-Item $destinationFile -Force
        if ( ($destItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and ($destItem.Target -eq $file.FullName) ) {
            Write-Path -Status "Exists" -Path $destinationFile -Link_Path $destItem.Target
            continue
        }
    }

    if (Test-Path $destinationFile) {
        Write-Output "Adopt?:          $destinationFile"
        $moveFile = $false
        if ($AutoApprove) {
            $moveFile = $true
            Write-VerboseCustom "+ AutoApprove adopting file"
        }
        else {
            $response = Read-Host "? Do you want to move this file to the dotfiles folder? (Y/N)"
            if ($response -match '^(Y|y)') {
                $moveFile = $true
            }
        }
        if ($moveFile) {
            Write-VerboseCustom "+ Moving file $destinationFile to $($file.FullName)"
            if (-not $DryRun) {
                Move-Item -Path $destinationFile -Destination $file.FullName -Force
            }
        }
        else {
            Write-VerboseCustom "+ Not moving file $destinationFile"
            continue
        }
    }

    if (Test-Path $destinationFile) {
        Write-Path -Status "Conflict" -Path $destinationFile -Link_Path $destItem.Target
        continue
    }

    Write-Path -Status "Queued Symlink" -Path $destinationFile -Link_Path $file.FullName

    # Create a command string for this symbolic link. Use double quotes to embed the paths.
    $cmd = "New-Item -ItemType SymbolicLink -Path `"$destinationFile`" -Target `"$($file.FullName)`""
    $SymlinkCommands += $cmd
    $CreatedLinkCount++
}

# ==============================================================================
# Final Summary Output (Folders Created, Symlinks Queued)
# ==============================================================================

Write-Host ""
if ($DryRun) {
    Write-Host "Dry Run Mode Enabled."
    Write-Host "Would have Created $CreatedFolderCount Folders"
    Write-Host "Would have Queued $CreatedLinkCount Symbolic Link Creations"
    exit 0
}
else {
    Write-Host "Created $CreatedFolderCount Folders"
    Write-Host "Queued $CreatedLinkCount Symbolic Link Creations"
}

# ==============================================================================
# Show the exact list of pending symlinks & prompt for confirmation
# ==============================================================================

if ($SymlinkCommands.Count -gt 0) {
    Write-Host ""
    Write-Host "The following symbolic links are queued to be created using Admin:"
    foreach ($cmd in $SymlinkCommands) {
        Write-Host "  $cmd"
    }
    Write-Host ""
    # Prompt for Y/N confirmation
    $response = Read-Host "? Do you want to create these symbolic links (requires admin)? (Y/N)"
    if ($response -notmatch '^(Y|y)') {
        Write-Host "Symbolic link creation aborted by user."
        exit 1
    }

    # ==============================================================================
    # Execute Symlink Commands in Elevated Process Using a Single Combined Command
    # ==============================================================================

    # Combine commands into one single string using "&&"
    $combinedCommand = $SymlinkCommands -join " && "

    Write-Host ""
    Write-Host "Preparing to create symbolic links with elevated privileges..."

    # Check if running as admin.
    if (-not (Test-Admin)) {
        Write-Host "Requesting admin privileges to create symbolic links..."
        Start-Process -FilePath pwsh -Verb runAs -ArgumentList "-NoProfile", "-Command", $combinedCommand
    }
    else {
        Write-Host "Running in admin mode. Creating symbolic links..."
        pwsh -NoProfile -Command $combinedCommand
    }

    Write-Host "Symbolic link creation process initiated."
}
