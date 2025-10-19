# Get-DiskUsage.psm1
# Exports: Get-DiskUsage, alias 'du'

function Format-Size {
    param(
        [long]$Bytes,
        [switch]$HumanReadable
    )
    if (-not $HumanReadable) {
        return $Bytes
    }
    $units = @('B', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    if ($Bytes -lt 1024) {
        return "$Bytes$($units[0])"
    }

    $i = [math]::Floor([math]::Log([double]$Bytes, 1024))

    if ($i -ge $units.Count) {
        $i = $units.Count - 1
    }

    $val = $Bytes / [math]::Pow(1024, $i)
    # Match GNU du style: no fixed decimals
    return ("{0:N0}{1}" -f $val, $units[$i])
}

function Resolve-ExcludePatterns {
    param(
        [string]$ExcludeFrom,
        [string[]]$Exclude
    )
    $patterns = @()
    if ($ExcludeFrom) {
        if (-not (Test-Path -LiteralPath $ExcludeFrom)) {
            throw "Exclude file not found: $ExcludeFrom"
        }
        $fileLines = Get-Content -LiteralPath $ExcludeFrom -ErrorAction Stop
        $patterns += ($fileLines | Where-Object { $_ -and $_.Trim() -ne '' })
    }
    if ($Exclude) {
        $patterns += $Exclude
    }
    return $patterns
}

function Test-Excluded {
    param(
        [string]$FullPath,
        [string[]]$Patterns
    )
    if (-not $Patterns -or $Patterns.Count -eq 0) {
        return $false
    }
    $leaf = Split-Path -Leaf -Path $FullPath
    foreach ($p in $Patterns) {
        # Treat patterns as PowerShell wildcards, check leaf and full path
        if ($leaf -like $p -or $FullPath -like $p) {
            return $true
        }
    }
    return $false
}

function Remove-NonNormalItem {
    <#
    .SYNOPSIS
        Filters out items with problematic attributes (cloud/offline/sync).
    .DESCRIPTION
        Accepts pipeline input or a collection from Get-ChildItem.
        Removes objects with ReparsePoint, Offline, RecallOnOpen, or RecallOnDataAccess attributes.
    .EXAMPLE
        Get-ChildItem -Recurse | Remove-NonNormalItem
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Object]$InputObject
    )
    begin {
        $mask = [IO.FileAttributes]::ReparsePoint `
            -bor [IO.FileAttributes]::Offline `
            -bor [IO.FileAttributes]::RecallOnOpen `
            -bor [IO.FileAttributes]::RecallOnDataAccess
    }
    process {
        if ($null -ne $InputObject -and ($InputObject.Attributes -band $mask) -eq 0) {
            # stream out immediately; no accumulation
            $InputObject
        }
    }
}

function Get-DirSize {
    param(
        [string]$Path,
        [string[]]$ExcludePatterns
    )
    $total = 0L
    try {
        # Files directly under this directory
        $files = Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction Stop | Remove-NonNormalItem
    }
    catch {
        return 0L
    }

    foreach ($f in $files) {
        if (-not (Test-Excluded -FullPath $f.FullName -Patterns $ExcludePatterns)) {
            $total += ($f.Length)
        }
    }
    # Recurse into subdirectories unless excluded
    try {
        $dirs = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction Stop | Remove-NonNormalItem
    }
    catch {
        $dirs = @()
    }

    foreach ($d in $dirs) {
        if (Test-Excluded -FullPath $d.FullName -Patterns $ExcludePatterns) {
            continue
        }
        $total += Get-DirSize -Path $d.FullName -ExcludePatterns $ExcludePatterns
    }
    return $total
}

function Get-DiskUsage {
    [CmdletBinding(PositionalBinding = $true)]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Path = @('.'),

        [Alias('d')]
        [int]$MaxDepth = 1,  # -1 = unlimited; 0 = summarize

        [Alias('h')]
        [switch]$HumanReadable,

        [Alias('s')]
        [switch]$Summarize,

        [Alias('X')]
        [string]$ExcludeFrom,

        # No alias named 'exclude' because it equals the parameter name
        [string[]]$Exclude
    )
    begin {
        $patterns = Resolve-ExcludePatterns -ExcludeFrom $ExcludeFrom -Exclude $Exclude
        $emit = {
            param($sizeBytes, $p)
            $sizeStr = Format-Size -Bytes $sizeBytes -HumanReadable:$HumanReadable
            $rel = $p
            try {
                $rel = Resolve-Path -LiteralPath $p -Relative -ErrorAction Stop
            }
            catch {}
            "{0,8}  {1}" -f $sizeStr, $rel
        }
        function Walk {
            param(
                [string]$Root,
                [int]$Depth,
                [int]$MaxDepth,
                [bool]$Summarize,
                [string[]]$Patterns
            )

            if (Test-Excluded -FullPath $Root -Patterns $Patterns) { return }

            if (-not (Test-Path -LiteralPath $Root)) {
                Write-Error "Path not found: $Root"
                return
            }

            # Always fetch and filter the root item first
            try {
                $item = Get-Item -LiteralPath $Root -Force -ErrorAction Stop | Remove-NonNormalItem
                if (-not $item) { return }  # filtered out due to attributes
            }
            catch { return }

            if (-not $item.PSIsContainer) {
                try { & $emit $item.Length $item.FullName } catch { Write-Error $_ }
                return
            }

            # Directory branch
            $size = Get-DirSize -Path $Root -ExcludePatterns $Patterns

            & $emit $size $Root
            if ($Summarize -or $MaxDepth -eq 0) { return }
            if ($MaxDepth -ge 0 -and $Depth -ge $MaxDepth) { return }

            $nextDepth = $Depth + 1
            try {
                $dirs = Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction Stop | Remove-NonNormalItem
            }
            catch { $dirs = @() }

            foreach ($d in $dirs) {
                if (Test-Excluded -FullPath $d.FullName -Patterns $Patterns) { continue }
                Walk -Root $d.FullName -Depth $nextDepth -MaxDepth $MaxDepth -Summarize:$Summarize -Patterns $Patterns
            }
        }
    }
    process {
        foreach ($p in $Path) {
            $resolved = $p
            try {
                $resolved = (Resolve-Path -LiteralPath $p -ErrorAction Stop).ProviderPath
            }
            catch {
            }
            if ($MaxDepth -eq 0) {
                $Summarize = $true
            }
            Walk -Root $resolved -Depth 0 -MaxDepth $MaxDepth -Summarize:$Summarize -Patterns $patterns
        }
    }
}

Set-Alias -Name du -Value Get-DiskUsage
Export-ModuleMember -Function Get-DiskUsage -Alias du
