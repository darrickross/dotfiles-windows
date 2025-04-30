# ----------------------------------------
# Check if Execution Policy Allows Script Execution
# ----------------------------------------
$effectivePolicy = Get-ExecutionPolicy -Scope Process
if ($effectivePolicy -eq 'Undefined') {
    $effectivePolicy = Get-ExecutionPolicy
}

$allowedPolicies = @('Unrestricted', 'RemoteSigned', 'Bypass')

if (-not ($allowedPolicies -contains $effectivePolicy)) {
    Write-Host "Your current execution policy is '$effectivePolicy', which may prevent this profile script from working properly." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To allow this script to run, you can set the policy to 'RemoteSigned' with the following command (requires administrator):" -ForegroundColor Cyan
    Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Green
    Write-Host ""
    Write-Host "Profile execution halted." -ForegroundColor Red
    return
}

# ----------------------------------------
# Load Write-Verbose / Write-Warning
# ----------------------------------------
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
    'Remove-EmptyFolders'
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
