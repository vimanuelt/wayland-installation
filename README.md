# Wayland Installation Script for FreeBSD, GhostBSD, and PolarisBSD

This script automates the installation and configuration of a native Wayland environment on FreeBSD using **seatd** for seat management. It installs essential packages such as **Sway**, **dbus**, and other utilities to set up a Wayland session. After completing the installation, the system will automatically reboot to apply the changes.

## Features

- Installs necessary Wayland components:
  - **Wayland**, **seatd** (for seat management), and **Sway** (a tiling window manager)
  - Dependencies like **libinput**, **wlroots**, **xwayland**
- Configures LightDM to launch **Sway** as the default session
- Automatically adds the specified user to the **seatd** group for input device management
- Ensures environment variables required for Wayland sessions are correctly set
- Restarts LightDM and reboots the system upon completion to apply all changes

## Requirements

- FreeBSD, GhostBSD, or PolarisBSD system with internet access
- Root privileges to execute the script

## Usage

### 1. Download the Script

Save the script as `install_wayland.sh`:

```sh
fetch https://github.com/vimanuelt/wayland-installation/install_wayland.sh
```

Alternatively, you can manually create the script:

```sh
nano install_wayland.sh
```

Paste the contents of the `install_wayland.sh` script and save it.

### 2. Make the Script Executable

Run the following command to make the script executable:

```sh
chmod +x install_wayland.sh
```

### 3. Run the Script

Execute the script with root privileges:

```sh
sudo ./install_wayland.sh
```

### 4. Automatic Reboot

After the installation and configuration are complete, the system will automatically reboot to apply all changes. After rebooting, you can log in and select **Sway** in the **LightDM** login screen.

### 5. Select Sway in LightDM

Once the system reboots, select **Sway** from the LightDM session options and log in.

## Script Overview

- **Essential Packages**: The script installs the following essential packages:
  - `wayland`, `seatd`, `sway`, `libinput`, `wlroots`, `mesa-libs`, `xwayland`, `dbus`
  
- **Services**:
  - Automatically enables and starts the **seatd** and **dbus** services to ensure proper input device and session management.
  
- **LightDM Configuration**:
  - Configures **LightDM** to launch **Sway** as the default session and disables launching X11.

- **Environment Configuration**:
  - Ensures that **Wayland**-related environment variables (`XDG_SESSION_TYPE=wayland` and `XDG_RUNTIME_DIR`) are correctly set in **/etc/profile**.

## Customization

You can modify the script to add or remove specific packages by editing the `ESSENTIAL_PACKAGES` variable.

## Troubleshooting

1. **Script Requires Root Privileges**:
   - Ensure you're running the script with root privileges using `sudo`.

2. **Internet Connection Required**:
   - The script needs internet access to install the packages using `pkg`.

3. **LightDM Not Showing Sway**:
   - Ensure **sway.desktop** is properly configured in **/usr/local/share/xsessions**.
   - Check that **LightDM** is configured to use **Sway** as the session by inspecting **lightdm.conf**.

4. **Check Logs**:
   - If any errors occur, check **/var/log/lightdm/lightdm.log** for **LightDM**-related issues or review the script's output for any other error messages.

5. **Sway Not Starting**:
   - Ensure that the **seatd** and **dbus** services are running:
     ```sh
     service seatd status
     service dbus status
     ```

   - Check your **~/.local/share/sway/log** for more detailed error information if Sway doesn't start.

