function Remove-EmptyFolders {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeRoot
    )

    begin {
        # collect all valid paths
        $paths = @()
    }

    process {
        if (Test-Path $Path -PathType Container) {
            $paths += (Resolve-Path $Path).ProviderPath
        }
        else {
            Write-Error "Path '$Path' does not exist or is not a directory."
        }
    }

    end {
        foreach ($start in $paths) {
            # Get all subdirectories, deepest first
            $dirs = Get-ChildItem -Path $start -Directory -Recurse -Force |
            Sort-Object FullName -Descending

            foreach ($dirInfo in $dirs) {
                $dir = $dirInfo.FullName
                # If directory contains no files or subdirectories...
                if (-not (Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($dir, 'Remove empty directory')) {
                        Remove-Item -Path $dir -Force
                        Write-Verbose "Removed empty directory: $dir"
                    }
                }
            }

            # Optionally remove the root itself if it's empty
            if ($IncludeRoot) {
                if (-not (Get-ChildItem -Path $start -Force -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($start, 'Remove empty root directory')) {
                        Remove-Item -Path $start -Force
                        Write-Verbose "Removed empty root directory: $start"
                    }
                }
            }
        }
    }
}