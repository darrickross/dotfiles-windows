<#
.SYNOPSIS
    Replicate PowerShell module folders and create symbolic links in WindowsPowerShell.
.DESCRIPTION
    Mirrors the entire folder structure under 'PowerShell' into 'WindowsPowerShell', then for each file,
    it creates a symbolic link pointing back to the original. Supports dry-run via -WhatIf, verbosity, and conflicts resolution.
.PARAMETER ScriptLocation
    Base path where the script resides (used to locate the Documents folder).
.PARAMETER DocumentsFolder
    Name of the Documents subfolder under ScriptLocation. Defaults to 'Documents'.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ScriptLocation = (Split-Path -Parent $PSCommandPath),
    [string]$DocumentsFolder = 'Documents'
)

# ==============================================================================
# Outputs a status label and path (and optional link target) with consistent formatting
# ==============================================================================
function Write-ItemStatus {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Exists', 'Queued', 'Conflict')]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [string]$TargetPath = ''
    )
    # determine colors and plain text
    switch ($Status) {
        'Queued' { $bg = 'Green'; $text = 'Queued' }
        'Exists' { $bg = ''; $text = 'Exists' }
        'Conflict' { $bg = 'Red'; $text = 'Conflict' }
    }
    # common padding
    $maxStatusLen = 8
    $padLen = $maxStatusLen - $text.Length + 1
    $padding = ' ' * $padLen

    # print status word (colored)…
    if ($bg) {
        Write-Host -NoNewline -BackgroundColor $bg $text
    }
    else {
        Write-Host -NoNewline $text
    }
    # …then uncolored colon and padding
    Write-Host -NoNewline ':'
    Write-Host -NoNewline $padding
    Write-Host " $RelativePath"

    # If a Target Path was provided print it
    if ($TargetPath) {
        $padding = ' ' * ($maxStatusLen + 6)
        Write-Host -NoNewline $padding
        Write-Host "-> $TargetPath"
    }
}

# ==============================================================================
# Write a Section Block
# ==============================================================================
function Write-Section {
    param([string]$Title)
    $sep = '=' * 80
    Write-Host "`n$sep"
    Write-Host "==  $Title"
    Write-Host "$sep`n"
}

# ==============================================================================
# Main Sync PS Module
# ==============================================================================
function Sync-PSModules {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] [string]$ScriptLocation,
        [Parameter(Mandatory)] [string]$DocumentsFolder
    )

    $basePath = Join-Path $ScriptLocation $DocumentsFolder
    $sourceRoot = Join-Path $basePath 'PowerShell'
    $destRoot = Join-Path $basePath 'WindowsPowerShell'

    $QueuedFolders = @()
    $QueuedLinks = @()
    $ConflictLinks = @()
    $ResolveConflicts = @()

    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        Write-Section 'DRY RUN MODE'
    }

    # ==============================================================================
    # Early Validations
    # ==============================================================================
    Write-Section 'Validating Paths'
    Write-Host "Source:      $sourceRoot"
    Write-Host "Destination: $destRoot"

    if (-not (Test-Path $sourceRoot -PathType Container)) {
        Write-Host 'ERROR: Source path does not exist. Aborting.'; throw
    }
    if (-not (Test-Path $destRoot -PathType Container)) {
        $QueuedFolders += $destRoot
    }

    # ==============================================================================
    # Scan folders
    # ==============================================================================
    Write-Section 'Scanning Folders'
    Get-ChildItem -Path $sourceRoot -Directory -Recurse | ForEach-Object {
        $relFull = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $fullTarget = Join-Path $destRoot $relFull
        $relative = ".\" + $fullTarget.Substring($basePath.Length + 1)
        if (Test-Path $fullTarget) {
            Write-ItemStatus `
                -Status Exists `
                -RelativePath $relative
        }
        else {
            $QueuedFolders += $fullTarget
            Write-ItemStatus `
                -Status Queued `
                -RelativePath $relative
        }
    }

    # ==============================================================================
    # Scan symbolic links
    # ==============================================================================
    Write-Section 'Scanning Symbolic Links'
    Get-ChildItem -Path $sourceRoot -File -Recurse | ForEach-Object {
        $relFull = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $fullLink = Join-Path $destRoot $relFull
        $relative = ".\" + $fullLink.Substring($basePath.Length + 1)
        if (Test-Path $fullLink) {
            $item = Get-Item $fullLink -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and ($item.Target -eq $_.FullName)) {
                Write-ItemStatus `
                    -Status Exists `
                    -RelativePath $relative -TargetPath $_.FullName
            }
            else {
                $ConflictLinks += [pscustomobject]@{ Link = $fullLink; Current = $item.Target; Expected = $_.FullName; Relative = $relative }
                Write-ItemStatus `
                    -Status Conflict `
                    -RelativePath $relative
            }
        }
        else {
            $QueuedLinks += [pscustomobject]@{ Link = $fullLink; Target = $_.FullName; Relative = $relative }
            Write-ItemStatus `
                -Status Queued `
                -RelativePath $relative `
                -TargetPath $_.FullName
        }
    }

    # ==============================================================================
    # Resolve conflicts
    # ==============================================================================
    if ($ConflictLinks.Count) {
        Write-Section 'Resolving Conflicts'
        # define four choices: Yes, Yes to All, No, No to All
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Resolve this conflict'),
            [System.Management.Automation.Host.ChoiceDescription]::new('Yes to &All', 'Resolve all conflicts'),
            [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip this conflict'),
            [System.Management.Automation.Host.ChoiceDescription]::new('No to A&ll', 'Skip all remaining conflicts')
        )
        $default = 0
        $processAll = $false
        $skipAll = $false

        foreach ($conf in $ConflictLinks) {
            if ($skipAll) { break }

            Write-Host "Conflict: $($conf.Relative)"
            Write-Host "    Current Dest:  $($conf.Current)"
            Write-Host "    Expected Dest: $($conf.Expected)"

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
    # Show Summary Plan
    # ==============================================================================
    Write-Section 'Queued Folders'
    $QueuedFolders | Sort-Object -Unique | ForEach-Object {
        $rel = ".\" + $_.Substring($basePath.Length + 1)
        Write-Host "Queue Folder:  $rel"
    }
    Write-Section 'Queued Symlinks'
    $QueuedLinks | ForEach-Object { Write-Host "Queue Symlink: $($_.Relative) -> $($_.Target)" }

    if ($PSBoundParameters.ContainsKey('WhatIf')) { return }

    if ($QueuedFolders.Count -gt 0 -and $QueuedLinks.Count -gt 0) { return }

    # ==============================================================================
    # Approval to Apply Changes
    # ==============================================================================

    Write-Host ""
    # Prompt for Y/N confirmation
    $response = Read-Host "? Do you want to apply these changes (Symbolic links might require admin)? (Y/N)"
    if ($response -notmatch '^(Y|y)') {
        Write-Host "Symbolic link creation aborted by user."
        exit 1
    }

    # ==============================================================================
    # Apply
    # ==============================================================================
    Write-Section 'Applying Changes'
    foreach ($f in $QueuedFolders | Sort-Object -Unique) {
        if (-not (Test-Path $f)) {
            if ($PSCmdlet.ShouldProcess($f, 'Create folder')) {
                New-Item -Path $f -ItemType Directory -Force
            }
        }
    }
    foreach ($l in $QueuedLinks) {
        if ($PSCmdlet.ShouldProcess($l.Link, 'Create symbolic link')) {
            New-Item -Path $l.Link -ItemType SymbolicLink -Value $l.Target -Force
        }
    }
    foreach ($c in $ResolveConflicts) {
        if ($PSCmdlet.ShouldProcess($c.Link, 'Resolve conflict')) {
            Remove-Item -Path $c.Link -Force
            New-Item -Path $c.Link -ItemType SymbolicLink -Value $c.Expected -Force
        }
    }

    # ==============================================================================
    # Summary
    # ==============================================================================
    Write-Section 'Summary'
    $newFolders = ($QueuedFolders | Where-Object { -not(Test-Path $_) }).Count
    $newLinks = $QueuedLinks.Count + $ResolveConflicts.Count
    Write-Host "Created $newFolders folders, $newLinks symbolic links (including fixes)."
}

# Entry
Sync-PSModules -ScriptLocation $ScriptLocation -DocumentsFolder $DocumentsFolder @PSBoundParameters
