# dotfiles-windows

## Summary

This repository is my `dotfiles` for the windows systems I use. This standardizes configurations and environment setups. Streamlining the process of configuring new systems by managing personal settings, scripts, and system tweaks in one central location.

## Requirements

### PowerShell 7

Install PowerShell 7 via [winget](https://docs.microsoft.com/en-us/windows/package-manager/winget/) using the command:

```ps
winget install --id Microsoft.PowerShell --source winget
```

After installation, restart your terminal session.

### Git

Ensure Git is installed to clone the repository.

## Applying Dotfiles to a New System

Follow these steps to deploy your dotfiles:

1. **Define Your Dotfiles Directory:**
   Decide where your dotfiles repository will reside. For example:

   ```ps
   $DotFileDir = "$HOME\projects\dotfiles-windows"
   ```

2. **Clone the Repository:**
   Use Git to clone the repository into your chosen location:

   ```ps
   git clone git@github.com:darrickross/dotfiles-windows.git $DotFileDir
   ```

3. **Preview the Deployment Changes:**
   Navigate into the repository directory and run a dry run to see what changes will be applied:

   ```ps
   cd $DotFileDir
   pwsh -ExecutionPolicy Bypass -File .\Deploy-Dotfiles.ps1 -DestinationFolder $HOME -DotfilesFolder $DotFileDir -DryRun
   ```

4. **Apply the Dotfiles:**
   Once you’re satisfied with the preview, execute the following command to apply the changes:

   ```ps
   pwsh -ExecutionPolicy Bypass -File .\Deploy-Dotfiles.ps1 -DestinationFolder $HOME -DotfilesFolder $DotFileDir
   ```

## Why is an Admin Prompt Required?

Running the deployment script may require administrative privileges in order to:

- Create symbolic links.

This is a feature of Windows as outlined by [bk2204 - in this Stack Overflow post](https://stackoverflow.com/a/64992080).

## .dotfile-ignore File

The `.dotfile-ignore` file lists patterns or specific files/folders that should be excluded from deployment. This helps in preventing unnecessary or sensitive files from being copied during the configuration process.

### Examples of .dotfile-ignore Entries

#### Temporary Scripts

```ignore
temp.ps1
```

#### Documentation Files

```ignore
README.md
```

#### Private Configurations

```ignore
secrets/
```

By listing these in the `.dotfile-ignore` file, you ensure that only the intended files are deployed, keeping your environment clean and secure.

Happy configuring!
