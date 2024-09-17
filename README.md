# Wayland Installation Script for FreeBSD, GhostBSD, and PolarisBSD

This script automates the installation of a native Wayland environment on FreeBSD using **seatd** for seat management. It installs essential packages like **Sway**, **dbus**, and other utilities to set up a Wayland session.

## Features

- Installs the necessary Wayland components, including:
  - **seatd** for seat management
  - **Sway** tiling window manager
  - **libinput**, **wlroots**, **xwayland**, and other essential packages
- Optionally installs additional Wayland-compatible tools like:
  - **Alacritty** terminal
  - **foot** terminal
  - **swaylock** screen locker
  - **noto** fonts
  - **grim** (screenshot tool) and **slurp** (selection tool)
- Automatically adds the specified user to the `seatd` group
- Configures environment variables for Wayland

## Requirements

- FreeBSD or GhostBSD or PolarisBSD system with internet access
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
sudo sh install_wayland.sh
```

### 4. Follow the Prompts

The script will ask for:
- A username to add to the `seatd` group
- Whether you want to install optional packages (like terminals, fonts, etc.)

Follow the prompts to complete the installation.

### 5. Log Out and Log Back In

Once the script finishes, log out and log back in to apply the group changes and environment variables.

### 6. Start Sway

After logging back in, start **Sway** (or another Wayland compositor) with the following command:

```sh
sway
```

## Script Overview

- **Essential Packages**: The script installs the following essential packages:
  - `seatd`, `wayland`, `wayland-protocols`, `sway`, `libinput`, `wlroots`, `mesa-libs`, `xwayland`, `dbus`
  
- **Optional Packages**: If chosen, the script also installs:
  - `alacritty`, `foot`, `swaylock`, `swayidle`, `grim`, `slurp`, `noto`

- **Services**:
  - Enables and starts the **seatd** and **dbus** services automatically.
  
- **Environment Configuration**:
  - Configures the environment variables for Wayland in the appropriate profile file (`.profile`, `.bash_profile`, or `.zprofile` depending on the shell).

## Customization

You can modify the script to add or remove specific packages by editing the `ESSENTIAL_PACKAGES` and `OPTIONAL_PACKAGES` variables.

## Troubleshooting

1. **Script Requires Root Privileges**:
   - Ensure you're running the script with root privileges using `sudo`.

2. **Internet Connection Required**:
   - The script needs internet access to install the packages using `pkg`.

3. **Check Logs**:
   - If any errors occur, check `/var/log/messages` for system errors or review the output from the script.

4. **Sway Not Starting**:
   - Ensure that **seatd** and **dbus** services are running:
     ```sh
     service seatd status
     service dbus status
     ```

   - Check your `~/.local/share/sway/log` for more detailed error information if Sway doesn't start.

