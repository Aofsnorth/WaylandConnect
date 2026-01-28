Fix Android Build & Implement Linux Standalone Autostart

This task addresses the build crash on Android and implements the "Start on Boot" functionality for the Linux Desktop target.

## Status: Ready for Verification

### 1. Fix Android Build Crash (Completed)
- **Error**: `Argument type 'Null' can't be assigned to parameter type 'String'`.
- **Fix**: Updated `lib/main.dart` to assign a valid string (`"preparing connection..."`) to `initialNotificationContent` instead of `null`.
- **File**: `lib/main.dart` (Line 75)

### 2. Implement "Start on Boot" for Linux (Completed)
- **Goal**: Allow the Flutter Linux app to start automatically on login.
- **Implementation**: 
  - Modified `SettingsScreen` (`lib/screens/settings_screen.dart`) to detect `Platform.isLinux`.
  - **On Toggle ON**: Creates a standard XDG Desktop Entry at `~/.config/autostart/wayland_connect.desktop`.
  - **On Toggle OFF**: Deletes this file.
  - **Path Handling**: Automatically resolves the executable path, supporting both development builds and AppImages.

### 3. Verification Steps
Since you have a running session, you can verify this manually or allow me to run a test script.

**Manual Verification:**
1. Run the app on Linux: `flutter run -d linux`
2. Go to **Settings** > **Start on Boot**.
3. Toggle it **OFF** and then **ON**.
4. Check the file system:
   ```bash
   cat ~/.config/autostart/wayland_connect.desktop
   ```
   *Expect to see a valid `.desktop` file pointing to your flutter executable.*

**Automated Verification (Optional):**
I can run a script to simulate the toggle logic if you prefer not to restart the UI.
