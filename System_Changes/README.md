# System Changes

## How to Import these Registry Changes

1. Open Admin Terminal
2. `reg import "C:\path\to\some_registry_change.reg"`

## Configure Nerd Font

### Install Nerd Font

1. Go to [Nerd Fonts Releases](https://github.com/ryanoasis/nerd-fonts/releases).
2. Download a `.zip` file for Windows (choose a font you like, e.g., `0xProto`).
3. Unzip the archive.
4. Locate the `.ttf` font files.
5. Right-click the font file(s) and choose **Install**.

### Configure VSCode to Use Nerd Font

Edit your VSCode `settings.json` (open via Ctrl+Shift+P → "Preferences: Open Settings (JSON)"):

```json
{
  "editor.fontFamily": "'0xProto Nerd Font Mono', Consolas, 'Courier New', monospace",
  "editor.fontLigatures": true,
  "terminal.integrated.fontFamily": "0xProto Nerd Font Mono",
  "terminal.integrated.fontLigatures.enabled": true
}
```

### Configure Windows Terminal / WSL to Use Nerd Font

1. Open **Windows Terminal**.
2. Click the down arrow ˅ next to the tab bar and select **Settings**.

> [!NOTE]
> You can reset these options if you changed the default windows terminal ships with using the Blue Left arrow on the Font face option.

#### Option A: Set Default Font for All Profiles

- In the sidebar, click **Profiles** → **Defaults**.
- Go to the **Appearance** tab.
- Under **Font face**, select `0xProto Nerd Font Mono`.
- Click Save

#### Option B: Set Font for a Specific Profile

- In the sidebar, click the specific profile (e.g., Ubuntu, Command Prompt).
- Go to the **Appearance** tab.
- Under **Font face**, select `0xProto Nerd Font Mono`.
- Click Save

## Allow Symbolic Link Creation

### Grant Create Symbolic Link Privilege via Group Policy

1. **Open** the Group Policy Management Console
   - Press Win + R, type `gpmc.msc`, and press Enter.

2. **Navigate** to:
   - **Computer Configuration**
   - **Windows Settings**
   - **Security Settings**
   - **Local Policies**
   - **User Rights Assignment**

3. In the right pane, **double-click** **Create symbolic links**.

4. Click **Add User or Group…**.

5. **Enter** the name of the user or group you want to grant this privilege to, then click **OK**.
