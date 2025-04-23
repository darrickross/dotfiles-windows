# Load Write-Verbose/Write-Warning
try {
    Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
}
catch {
    Write-Host "WARNING: Could not load Microsoft.PowerShell.Utility: $_" -ForegroundColor Yellow
}

# ----------------------------------------
# Modules to try to import on startup
# ----------------------------------------
$ModulesToImport = @(
    'Compare-FileHash'
)

foreach ($Module in $ModulesToImport) {
    if (Get-Module -ListAvailable -Name $Module) {
        try {
            Import-Module $Module -ErrorAction Stop
            Write-Verbose "Imported module '$Module'."
        }
        catch {
            Write-Warning "Failed to import module '$Module': $_"
        }
    }
    else {
        Write-Verbose "Module '$Module' not found; skipping."
    }
}
