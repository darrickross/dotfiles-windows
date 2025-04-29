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
      2. Collects ignore rules (.dotfile-ignore + script itself).
      3. Scans and queues all new folders to create.
      4. Scans and queues all symlinks to create, tracking conflicts separately.
      5. Shows a “plan” summary of folders, links, and conflicts.
      6. Prompts for confirmation, then applies all changes (honoring -DryRun and -WhatIf).
.PARAMETER DotfilesFolder
    Path to the dotfiles folder. Defaults to the current directory.
.PARAMETER DestinationFolder
    The destination directory where symlinks will be created. Defaults to $env:USERPROFILE.
.PARAMETER WhatIf
    If set, no real changes are made (uses -WhatIf).
.PARAMETER VerboseOutput
    If set, additional informational output is shown.
.PARAMETER AutoApprove
    If set, existing destination files are automatically moved without prompting.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$DotfilesFolder = (Get-Location).Path,
    [string]$DestinationFolder = $env:USERPROFILE,
    [switch]$VerboseOutput,
    [switch]$AutoApprove
)

# ==============================================================================
# Helper Functions
# ==============================================================================

function Test-CanUserCreateSymbolicLink {
    $canCreate = $true
    $tmpTarget = Join-Path $env:TEMP 'symlink_test_target.txt'
    $tmpLink = Join-Path $env:TEMP ("symlink_test_{0}.lnk" -f [guid]::NewGuid())
    # create a dummy target file
    "test" | Out-File $tmpTarget -Force

    try {
        # attempt to make a link
        New-Item -Path $tmpLink -ItemType SymbolicLink -Value $tmpTarget -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $canCreate = $false
    }

    # clean up
    if (Test-Path $tmpLink) { Remove-Item $tmpLink -Force }
    if (Test-Path $tmpTarget) { Remove-Item $tmpTarget -Force }

    return $canCreate
}

function Write-VerboseCustom {
    param ([string]$Message)
    if ($VerboseOutput) { Write-Host $Message }
}

function IsValidGitIgnorePath {
    param ([string]$Pattern)
    $p = $Pattern.Trim()
    if ([string]::IsNullOrEmpty($p) -or $p.Contains(":")) { return $false }
    return ($p -match '^(?:!?)[\w\-\.\*\/]+\/?$')
}

function IsIgnored {
    param ([string]$RelativePath)
    foreach ($pattern in $IgnoredPaths) {
        if ($RelativePath -like $pattern -or $RelativePath.StartsWith($pattern)) {
            return $true
        }
    }
    return $false
}

function Write-ItemStatus {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'Added',
            'Adopt',
            'Adopted',
            'Conflict',
            'Create',
            'Created',
            'Exists',
            'Ignored',
            'Invalid',
            'Queued',
            'Replace',
            'Removed'
        )]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$DestPath = ''
    )
    # determine colors and plain text
    switch ($Status) {
        'Added' { $bg = ''; $text = 'Added' }
        'Adopt' { $bg = ''; $text = 'Adopt' }
        'Adopted' { $bg = ''; $text = 'Adopted' }
        'Conflict' { $bg = 'DarkRed'; $fg = 'White'; $text = 'Conflict' }
        'Create' { $bg = ''; $text = 'Create' }
        'Created' { $bg = ''; $text = 'Created' }
        'Exists' { $bg = ''; $text = 'Exists' }
        'Ignored' { $bg = 'DarkGray'; $fg = 'DarkYellow'; $text = 'Ignored' }
        'Invalid' { $bg = 'DarkRed'; $fg = 'White'; $text = 'Invalid' }
        'Queued' { $bg = 'DarkGreen'; $fg = 'Black'; $text = 'Queued' }
        'Replace' { $bg = ''; $text = 'Replace' }
        'Remove' { $bg = ''; $text = 'Remove' }
    }
    # common padding
    $maxStatusLen = 8
    $padLen = $maxStatusLen - $text.Length + 1
    $padding = ' ' * $padLen

    # print status word (colored)…
    if ($bg) {
        Write-Host `
            -NoNewline `
            -BackgroundColor $bg `
            -ForegroundColor $fg `
            $text
    }
    else {
        Write-Host `
            -NoNewline `
            $text
    }
    # …then uncolored colon and padding
    Write-Host -NoNewline ':'
    Write-Host -NoNewline $padding
    Write-Host " $Path"

    # If a Target Path was provided print it
    if ($DestPath) {
        $padding = ' ' * ($maxStatusLen + 6)
        Write-Host -NoNewline $padding
        Write-Host "-> $DestPath"
    }
}

function Write-Section {
    param([string]$Title)
    $sep = '=' * 80
    Write-Host "`n$sep"
    Write-Host "==  $Title"
    Write-Host "$sep`n"
}

# ==============================================================================
# Prep & Validate
# ==============================================================================

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Throw 'This script requires PowerShell 7+ for command chaining.'
}

if ($PSBoundParameters.ContainsKey('WhatIf')) {
    Write-Section 'DRY RUN MODE'
}

$DotfilesFolder = (Resolve-Path $DotfilesFolder).Path
$DestinationFolder = (Resolve-Path $DestinationFolder).Path
$ScriptPath = $MyInvocation.MyCommand.Path

if (-not (Test-Path $DotfilesFolder -PathType Container) -or
    -not (Test-Path $DestinationFolder -PathType Container)) {
    Throw "Either DotfilesFolder or DestinationFolder does not exist."
}

# Build ignore list
Write-Section 'Building Ignore List'
$IgnoredPaths = @()

# Add dotfile to the list
$dotfile_ignore = '.dotfile-ignore'
$IgnoredPaths += $dotfile_ignore
Write-ItemStatus -Status Added -Path $dotfile_ignore

# Add this script
$thisScriptFile = Split-Path $ScriptPath -Leaf
$IgnoredPaths += ($thisScriptFile)
Write-ItemStatus -Status Added -Path $thisScriptFile

# Read items from ignore list
$dotIgnore = Join-Path $DotfilesFolder $dotfile_ignore
if (Test-Path $dotIgnore) {
    Get-Content $dotIgnore | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object {
        if (IsValidGitIgnorePath $_) {
            $IgnoredPaths += $_
            Write-ItemStatus -Status Added -Path $_
        }
        else {
            Write-ItemStatus -Status Invalid -Path $_
        }
    }
}

# ==============================================================================
# Scan Phase: Collect plan items
# ==============================================================================

$QueuedFolders = [System.Collections.ArrayList]@()
$QueuedLinks = [System.Collections.ArrayList]@()
$ConflictLinks = [System.Collections.ArrayList]@()
$ConflictFilesToAdopt = [System.Collections.ArrayList]@()
$ResolveConflicts = [System.Collections.ArrayList]@()
$ResolveAdoption = [System.Collections.ArrayList]@()

Write-Section 'Scanning Folders to Mirror'
$ScanDirectories = Get-ChildItem -Path $DotfilesFolder -Directory -Recurse | `
    Sort-Object FullName

foreach ($folder in $ScanDirectories) {
    $RelativePath = $folder.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')

    if (IsIgnored $RelativePath) {
        Write-ItemStatus -Status Ignored -Path $RelativePath
        continue
    }

    $target = Join-Path $DestinationFolder $RelativePath

    if (Test-Path $target) {
        Write-ItemStatus -Status Exists -Path $RelativePath
        continue
    }

    $QueuedFolders.Add($target) | Out-Null
    Write-ItemStatus -Status Queued -Path $RelativePath
}

Write-Section 'Scanning Files for Symlinks'
$ScanFiles = Get-ChildItem -Path $DotfilesFolder -File -Recurse | `
    Sort-Object FullName

foreach ($file in $ScanFiles) {
    $RelativePath = $file.FullName.Substring($DotfilesFolder.Length).TrimStart('\', '/')

    # Do we Ignore this relative path?
    if (IsIgnored $RelativePath) {
        Write-ItemStatus -Status Ignored -Path $RelativePath
        continue
    }

    $DestinationPath = Join-Path $DestinationFolder $RelativePath

    # Does the Destination Path Already Exist
    if (Test-Path $DestinationPath) {
        $item = Get-Item $DestinationPath -Force

        # Is this item a regular file (not symbolic link)
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $ConflictFilesToAdopt.Add([pscustomobject]@{
                    Relative        = $RelativePath
                    SymLinkTarget   = $file.FullName
                    SymLinkLocation = $DestinationPath
                }) | Out-Null
            Write-ItemStatus -Status Conflict -Path $RelativePath
            continue
        }

        # If this item is a Symbolic Link
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {

            # If this Symbolic Link is Already Correct
            if ($item.Target -eq $file.FullName) {
                Write-ItemStatus -Status Exists -Path $RelativePath -DestPath $file.FullName
                continue
            }
            # Otherwise Symbolic Link doesn't point to the file this script thinks it should
            else {
                $ConflictLinks.Add([pscustomobject]@{
                        SymLinkCurrent  = $item.Target
                        SymLinkLocation = $DestinationPath
                        SymLinkTarget   = $file.FullName
                        Relative        = $RelativePath
                    }) | Out-Null
                Write-ItemStatus -Status Conflict -Path $RelativePath -DestPath $file.FullName
                continue
            }
        }
    }

    # Otherwise Queue the Symbolic link to be created
    $QueuedLinks.Add([pscustomobject]@{
            SymLinkLocation = $DestinationPath
            SymLinkTarget   = $file.FullName
            Relative        = $RelativePath
        }) | Out-Null
    Write-ItemStatus -Status Queued  -Path $RelativePath -DestPath $file.FullName
}

$QueuedFolders = $QueuedFolders | Sort-Object -Unique
$QueuedLinks = $QueuedLinks | Sort-Object -Property Relative -Unique
$ConflictLinks = $QueuedLinks | Sort-Object -Property Relative -Unique
$ConflictFilesToAdopt = $ConflictFilesToAdopt | Sort-Object -Property Relative -Unique

# ==============================================================================
# Resolve Files to Adopt
# ==============================================================================

if ($ConflictFilesToAdopt.Count -gt 0) {
    Write-Section 'Resolving File to Adopt into dotfiles management'

    # define four choices: Yes, Yes to All, No, No to All
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Resolve this conflict'),
        [System.Management.Automation.Host.ChoiceDescription]::new('Yes to &All', 'Resolve all conflicts'),
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip this conflict'),
        [System.Management.Automation.Host.ChoiceDescription]::new('No to A&ll', 'Skip all remaining conflicts')
    )

    $default = 2 # No
    $processAll = $false
    $skipAll = $false

    foreach ($conf in $ConflictFilesToAdopt) {
        if ($skipAll) { break }

        Write-Host "$($conf.Relative)"
        Write-Host "    File:   $($conf.SymLinkLocation)"
        Write-Host "    To:     $($conf.SymLinkTarget)"
        # Write-Host "    Do you want to move the file into the dotfile folder?"

        if (-not $processAll) {
            $idx = $Host.UI.PromptForChoice('', '    Adopt this Conflict & Create Symbolic Link?', $choices, $default)
            switch ($idx) {
                0 { $resolve = $true }                      # Yes
                1 { $resolve = $true; $processAll = $true } # Yes to All
                2 { $resolve = $false }                     # No
                3 { $resolve = $false; $skipAll = $true }   # No to All
            }
        }
        else {
            # Already chosen “Yes to All”
            $resolve = $true
        }

        if ($resolve) {
            $ResolveAdoption += $conf
        }
    }

    if ($ResolveAdoption.Count -gt 0) {
        Write-Section 'Queued Conflicts to Fix'
        $ResolveAdoption | ForEach-Object { Write-Host "Fix: $($_.Relative)" }
    }
}

# ==============================================================================
# Resolve Conflicting Symbolic Links
# ==============================================================================

if ($ConflictLinks.Count -gt 0) {
    Write-Section 'Resolving Conflicts'

    # define four choices: Yes, Yes to All, No, No to All
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Resolve this conflict'),
        [System.Management.Automation.Host.ChoiceDescription]::new('Yes to &All', 'Resolve all conflicts'),
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip this conflict'),
        [System.Management.Automation.Host.ChoiceDescription]::new('No to A&ll', 'Skip all remaining conflicts')
    )
    $default = 2 # No
    $processAll = $false
    $skipAll = $false

    foreach ($conf in $ConflictLinks) {
        if ($skipAll) { break }

        Write-Host "Conflict: $($conf.Relative)"
        Write-Host "    Current Dest:   $($conf.SymLinkCurrent)"
        Write-Host "    Expected Dest:  $($conf.SymLinkTarget)"

        if (-not $processAll) {
            $idx = $Host.UI.PromptForChoice('', '    Replace this Conflict?', $choices, $default)
            switch ($idx) {
                0 { $resolve = $true }                      # Yes
                1 { $resolve = $true; $processAll = $true } # Yes to All
                2 { $resolve = $false }                     # No
                3 { $resolve = $false; $skipAll = $true }   # No to All
            }
        }
        else {
            # Already chosen “Yes to All”
            $resolve = $true
        }

        if ($resolve) {
            $ResolveConflicts += $conf
        }
    }

    if ($ResolveConflicts.Count) {
        Write-Section 'Queued Conflicts to Fix'
        $ResolveConflicts | ForEach-Object { Write-Host "Fix: $($_.Relative)" }
    }
}

# ==============================================================================
# Show Plan Summary
# ==============================================================================
Write-Section 'Plan Summary'

if ($QueuedFolders.Count -gt 0) {
    Write-Host "Folders to Create:"
    Write-Host ""

    foreach ($Folder in $QueuedFolders) {
        Write-ItemStatus `
            -Status Create `
            -Path $Folder
    }
}
else { Write-Host "No new folders required." }

Write-Host "`n--------------------"

if ($QueuedLinks.Count -gt 0) {
    Write-Host "Links to Create:"
    Write-Host ""
    foreach ($Symlink in $QueuedLinks) {
        Write-ItemStatus `
            -Status Create `
            -Path $Symlink.SymLinkLocation `
            -DestPath $Symlink.SymLinkTarget
    }
}
else { Write-Host "No new symlinks required." }

Write-Host "`n--------------------"

if ($ResolveAdoption.Count -gt 0) {
    Write-Host "Existing Files to Adopt:"
    Write-Host ""
    foreach ($adopt in $ResolveAdoption) {
        Write-ItemStatus `
            -Status Adopt `
            -Path $adopt.SymLinkLocation `
            -DestPath $adopt.SymLinkTarget
    }
}
else {
    Write-Host "No Files to Adopt detected."
}

Write-Host "`n--------------------"

if ($ResolveConflicts.Count -gt 0) {
    Write-Host "Conflicts to Resolve:"
    Write-Host ""
    foreach ($conf in $ResolveConflicts) {
        Write-ItemStatus `
            -Status Replace `
            -Path $conf.SymLinkLocation `
            -DestPath $conf.SymLinkTarget
    }
}
else {
    Write-Host "No conflicts detected."
}

# ==============================================================================
# DryRun / Confirmation
# ==============================================================================
if ($PSBoundParameters.ContainsKey('WhatIf')) {
    Write-Host ""
    Write-Host "DryRun (-WhatIf) enabled; no changes will be made."
    return
}

$ok = Read-Host "`nApply these changes? (Y/N)"
if ($ok -notmatch '^[Yy]') {
    Write-Host "Operation cancelled by user."
    return
}

# ==============================================================================
# Execution Phase
# ==============================================================================
Write-Section 'Applying Changes'

# 1) Create Folders
foreach ($f in $QueuedFolders | Sort-Object -Unique) {
    if ($PSCmdlet.ShouldProcess($f, 'New Folder')) {
        New-Item -ItemType Directory -Path $f -Force | Out-Null
    }
}

# 2) Adopt approved files
foreach ($adopt in $ResolveAdoption) {
    Move-Item -Path $adopt.SymLinkLocation -Destination $adopt.SymLinkTarget -Force
    Write-ItemStatus -Status Adopted -Path $adopt.SymLinkLocation
    $QueuedLinks.Add(
        [pscustomobject]@{
            SymLinkLocation = $adopt.SymLinkLocation
            SymLinkTarget   = $adopt.SymLinkTarget
            Relative        = $adopt.Relative
        }
    ) | Out-Null
}

# 3) Remove Approved Conflict Symlinks
foreach ($conflict in $ResolveConflicts) {
    Remove-Item -Path $conflict.SymLinkLocation -Confirm
    Write-ItemStatus -Status Removed -Path $conflict.SymLinkLocation
    $QueuedLinks.Add(
        [pscustomobject]@{
            SymLinkLocation = $conflict.SymLinkLocation
            SymLinkTarget   = $conflict.SymLinkTarget
            Relative        = $conflict.Relative
        }
    ) | Out-Null
}

if ($QueuedLinks.Count -eq 0) {
    return
}

if (Test-CanUserCreateSymbolicLink) {
    Write-Sections 'Create Queued Symbolic Links as Current User'
    foreach ($l in $QueuedLinks) {
        if ($PSCmdlet.ShouldProcess($l.SymLinkLocation, 'Create symbolic link')) {
            New-Item -Path $l.SymLinkLocation -ItemType SymbolicLink -Value $l.SymLinkTarget -Force
        }
    }
}
else {
    Write-Sections 'Create Queued Symbolic Links as Admin'
    Write-Host "Unable to create symbolic links under your current user permissions." -ForegroundColor DarkRed
    Write-Host ""

    $commands = $QueuedLinks | `
        ForEach-Object { "New-Item -Path `"$($_.SymLinkLocation)`" -ItemType SymbolicLink -Value `"$($_.SymLinkTarget)`" -Force" }

    $commandString = $commands -join '    &&    '

    Write-Host "The following command will be run as Administrator to provision them instead:" `
        -ForegroundColor Yellow `
        -BackgroundColor Black
    Write-Host ""
    Write-Host $commandString
    Write-Host ""

    $approve = Read-Host "Do you want to elevation and execution the above command as Administrator? (Y/N)"
    if ($approve -match '^[Yy]$') {
        Start-Process `
            -FilePath pwsh `
            -Verb RunAs `
            -ArgumentList "-NoProfile", "-Command", $commandString
    }
    else {
        Write-Host "Symlink creation canceled by user." `
            -ForegroundColor Yellow `
            -BackgroundColor Black
    }
}

Write-Host ""
Write-Host "All done."
