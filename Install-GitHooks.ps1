<#
.SYNOPSIS
    Points this repo's git config at the tracked .githooks folder.
.DESCRIPTION
    core.hooksPath is a per-clone git config setting, not a tracked file, so
    it doesn't survive a fresh clone on its own. Run this once after cloning
    (or re-run any time) to wire up .githooks/pre-commit, which keeps
    AppData\Roaming\Code\User\settings.json sorted by key on commit.
.PARAMETER RepoRoot
    Path to the repo root. Defaults to this script's own folder.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSCommandPath)
)

# ==============================================================================
# Outputs a status label and path with consistent formatting
# ==============================================================================
function Write-ItemStatus {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Exists', 'Queued', 'Conflict')]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$RelativePath
    )
    switch ($Status) {
        'Queued' { $bg = 'DarkGreen'; $fg = 'Black'; $text = 'Queued' }
        'Exists' { $bg = ''; $text = 'Exists' }
        'Conflict' { $bg = 'DarkRed'; $fg = 'White'; $text = 'Conflict' }
    }
    $maxStatusLen = 8
    $padLen = $maxStatusLen - $text.Length + 1
    $padding = ' ' * $padLen

    if ($bg) {
        Write-Host -NoNewline -BackgroundColor $bg -ForegroundColor $fg $text
    }
    else {
        Write-Host -NoNewline $text
    }
    Write-Host -NoNewline ':'
    Write-Host -NoNewline $padding
    Write-Host " $RelativePath"
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

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'This script requires PowerShell 7+.'
}

Write-Section 'Validating Environment'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git was not found on PATH.'
}
Write-ItemStatus -Status 'Exists' -RelativePath 'git'

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Warning 'pwsh was not found on PATH. The pre-commit hook shells out to pwsh and will fail without it.'
}
else {
    Write-ItemStatus -Status 'Exists' -RelativePath 'pwsh'
}

$hooksDir = Join-Path $RepoRoot '.githooks'
if (-not (Test-Path $hooksDir)) {
    throw "Expected hooks folder not found: $hooksDir"
}
Write-ItemStatus -Status 'Exists' -RelativePath '.githooks/'

Write-Section 'Configuring git'

Push-Location $RepoRoot
try {
    $current = git config --local --get core.hooksPath 2>$null

    if ($current -eq '.githooks') {
        Write-ItemStatus -Status 'Exists' -RelativePath 'core.hooksPath = .githooks'
    }
    else {
        if ($PSCmdlet.ShouldProcess('core.hooksPath', 'Set to .githooks')) {
            git config --local core.hooksPath .githooks
            Write-ItemStatus -Status 'Queued' -RelativePath 'core.hooksPath = .githooks'
        }
    }
}
finally {
    Pop-Location
}

Write-Host "`nDone. Commits touching AppData\Roaming\Code\User\settings.json will now be sorted by key automatically."
