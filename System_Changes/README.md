# System Changes

## How to Import these Registry Changes

1. Open Admin Terminal
2. `reg import "C:\path\to\some_registry_change.reg"`

## Changes to GPO

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
