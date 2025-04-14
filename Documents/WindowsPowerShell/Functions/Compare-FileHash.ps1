function Compare-FileHash {
    param (
        [Parameter(Mandatory = $true)][string]$FilePathA,
        [Parameter(Mandatory = $true)][string]$FilePathB,
        [ValidateSet("SHA256", "SHA1", "MD5")][string]$Algorithm = "SHA256"
    )

    # Compute file hashes
    $hashA = Get-FileHash -Path $FilePathA -Algorithm $Algorithm
    $hashB = Get-FileHash -Path $FilePathB -Algorithm $Algorithm

    # Output hashes with file paths
    Write-Output "$($hashA.Hash) - $($hashA.Path)"
    Write-Output "$($hashB.Hash) - $($hashB.Path)"

    # Output comparison result
    $areEqual = $hashA.Hash -eq $hashB.Hash
    Write-Output $areEqual

    # Return the boolean result
    return $areEqual
}
