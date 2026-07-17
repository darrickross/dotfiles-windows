#Requires -Version 7.0
<#
.SYNOPSIS
    Rewrites a JSON file with all object keys sorted (ordinal, recursive).

.DESCRIPTION
    Used as a git pre-commit hook (see .githooks/pre-commit) to keep
    AppData\Roaming\Code\User\settings.json sorted by key on every commit.
    Array element order is left untouched; only object property order changes.

.PARAMETER Path
    One or more JSON file paths to sort in place.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string[]]$Path
)

begin {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "Sort-JsonKeys.ps1 requires PowerShell 7+. Current version: $($PSVersionTable.PSVersion)"
    }

    function Write-SortedJson {
        param(
            [System.Text.Json.JsonElement]$Element,
            [System.Text.Json.Utf8JsonWriter]$Writer
        )

        switch ($Element.ValueKind) {
            'Object' {
                $Writer.WriteStartObject()
                $props = [System.Collections.Generic.List[System.Text.Json.JsonProperty]]::new()
                foreach ($p in $Element.EnumerateObject()) { $props.Add($p) }
                $props.Sort([Comparison[System.Text.Json.JsonProperty]] {
                        param($a, $b)
                        [string]::CompareOrdinal($a.Name, $b.Name)
                    })
                foreach ($p in $props) {
                    $Writer.WritePropertyName($p.Name)
                    Write-SortedJson -Element $p.Value -Writer $Writer
                }
                $Writer.WriteEndObject()
            }
            'Array' {
                $Writer.WriteStartArray()
                foreach ($item in $Element.EnumerateArray()) {
                    Write-SortedJson -Element $item -Writer $Writer
                }
                $Writer.WriteEndArray()
            }
            default {
                $Element.WriteTo($Writer)
            }
        }
    }
}

process {
    foreach ($file in $Path) {
        $resolved = Resolve-Path -LiteralPath $file
        $originalText = [System.IO.File]::ReadAllText($resolved)

        $docOptions = [System.Text.Json.JsonDocumentOptions]::new()
        $docOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        $docOptions.AllowTrailingCommas = $true
        $doc = [System.Text.Json.JsonDocument]::Parse([string]$originalText, $docOptions)

        try {
            $ms = [System.IO.MemoryStream]::new()
            $writerOptions = [System.Text.Json.JsonWriterOptions]::new()
            $writerOptions.Indented = $true
            $writerOptions.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
            $writer = [System.Text.Json.Utf8JsonWriter]::new($ms, $writerOptions)
            try {
                Write-SortedJson -Element $doc.RootElement -Writer $writer
            }
            finally {
                $writer.Flush()
                $writer.Dispose()
            }

            $sortedText = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) + "`n"
        }
        finally {
            $doc.Dispose()
        }

        if ($sortedText -eq $originalText) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($resolved, 'Sort JSON keys')) {
            [System.IO.File]::WriteAllText($resolved, $sortedText, [System.Text.UTF8Encoding]::new($false))
        }
    }
}
