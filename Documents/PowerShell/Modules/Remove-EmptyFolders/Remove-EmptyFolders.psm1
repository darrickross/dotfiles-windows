function Remove-EmptyFolders {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeRoot,

        [Parameter()]
        [switch]$Silent
    )

    begin {
        $paths = @()

        # get console width once
        $consoleWidth = $Host.UI.RawUI.BufferSize.Width

        # Whitespace padding to clear a status line with
        $spaces = " " * $consoleWidth
    }

    process {
        Write-Host "Getting List of directories in: $Path" -NoNewline
        Write-Host "`r" -NoNewline
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $paths += (Resolve-Path -LiteralPath $Path).ProviderPath
        }
        else {
            Write-Error "Path '$Path' does not exist or is not a directory."
        }
    }

    end {
        foreach ($start in $paths) {
            # Get all subdirectories, deepest first
            $dirs = Get-ChildItem -LiteralPath $start -Directory -Recurse -Force | `
                Sort-Object FullName -Descending

            foreach ($dirInfo in $dirs) {
                $dir = $dirInfo.FullName

                Write-Host $spaces -NoNewline
                Write-Host "`r" -NoNewline
                Write-Host "Processing: $dir" -NoNewline
                Write-Host "`r" -NoNewline

                # Try to enumerate; if it fails, skip
                try {
                    $children = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop
                }
                catch {
                    Write-Host $spaces -NoNewline
                    Write-Host "`r" -NoNewline
                    Write-Warning "Skipping unreadable directory: $dir"
                    continue
                }

                # If directory truly has no children, remove it
                if (-not $children) {
                    if ($PSCmdlet.ShouldProcess($dir, 'Remove empty directory')) {
                        Remove-Item -LiteralPath $dir -Force
                        if (-not $Silent) {
                            Write-Host $spaces -NoNewline
                            Write-Host "`r" -NoNewline
                            Write-Host "Removing: $dir"
                        }
                    }
                }
            }

            # Optionally remove the root itself if it's empty and readable
            if ($IncludeRoot) {
                try {
                    $rootChildren = Get-ChildItem -LiteralPath $start -Force -ErrorAction Stop
                }
                catch {
                    Write-Host $spaces -NoNewline
                    Write-Host "`r" -NoNewline
                    Write-Warning "Skipping unreadable root directory: $start"
                    continue
                }

                if (-not $rootChildren) {
                    if ($PSCmdlet.ShouldProcess($start, 'Remove empty root directory')) {
                        Remove-Item -LiteralPath $start -Force
                        if (-not $Silent) {
                            Write-Host $spaces -NoNewline
                            Write-Host "`r" -NoNewline
                            Write-Output "Removing: $start"
                        }
                    }
                }
            }
        }
        Write-Host $spaces -NoNewline
        Write-Host "`r" -NoNewline
    }
}
