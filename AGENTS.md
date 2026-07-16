# AGENTS.md

## What this repo is

Personal Windows dotfiles. The repo layout mirrors the destination layout: a
file at `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` in this repo
gets symlinked to `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
(and similarly for `AppData\Roaming\...`, `.ssh\...`, etc.). There is no
build step, package manifest, or test suite — "correctness" means the
PowerShell scripts run cleanly and the deployed symlink tree matches what's
in the repo.

## Key scripts

- `Deploy-Dotfiles.ps1` — walks the repo tree, mirrors folders and creates
  symlinks into `-DestinationFolder` (defaults to `$env:USERPROFILE`),
  respecting `.dotfile-ignore`. Supports `-WhatIf` (dry run), `-VerboseOutput`,
  `-AutoApprove`. Requires PowerShell 7+. Elevates to admin only if the
  current user lacks the "Create symbolic links" privilege.
- `Sync-PSModules.ps1` — mirrors `Documents\PowerShell\Modules\*` into
  `Documents\WindowsPowerShell\Modules\*` via symlinks, so Windows PowerShell
  5.1 sees the same modules as PowerShell 7.
- `.dotfile-ignore` — gitignore-style patterns excluded from deployment
  (distinct from `.gitignore`; read explicitly by `Deploy-Dotfiles.ps1`).

## Conventions to follow when editing scripts

- Target PowerShell 7+ syntax (`[CmdletBinding(SupportsShouldProcess = $true)]`,
  `&&`/`||` chaining). Scripts self-check `$PSVersionTable.PSVersion.Major`
  and throw if run under 5.1.
- Respect `-WhatIf` / `ShouldProcess` for anything that mutates the
  filesystem — wrap mutating calls in `if ($PSCmdlet.ShouldProcess(...))`.
- Reuse the existing `Write-ItemStatus` / `Write-Section` helper pattern for
  console output rather than introducing a new formatting style.
- Conflict resolution prompts use the four-way
  Yes/Yes-to-All/No/No-to-All `ChoiceDescription` pattern seen in both
  `Deploy-Dotfiles.ps1` and `Sync-PSModules.ps1` — match it for consistency.
- Never commit secrets. `AppData\Roaming\GitHub CLI\config.yml` is tracked
  (preferences only); `*hosts.yml` is deliberately git-ignored because it can
  hold a raw `gh` OAuth token on machines without keyring support. SSH keys
  live outside the repo (`.ssh\config` / `.ssh\configs\*` only reference an
  external `IdentityFile` path, e.g. a YubiKey resident key).

## Testing changes

There's no automated test suite. Verify script changes with a dry run before
trusting them:

```ps
pwsh -ExecutionPolicy Bypass -File .\Deploy-Dotfiles.ps1 -DestinationFolder <somewhere-safe> -DotfilesFolder . -WhatIf -VerboseOutput
```

Prefer pointing `-DestinationFolder` at a scratch directory rather than the
real `$HOME` when iterating, since applying creates real symlinks (and may
prompt for admin elevation).

## Registry changes

`System_Changes/Registry/*.reg` are manual, one-off tweaks — not deployed by
any script. They're imported by hand (`reg import ...` from an admin
terminal) per `System_Changes/README.md`. Don't wire these into the deploy
script; they're intentionally opt-in and machine-specific.
