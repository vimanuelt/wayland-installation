# Wayland Installation Script for FreeBSD, GhostBSD, and PolarisBSD

This script automates the installation of a native Wayland environment on FreeBSD using **seatd** for seat management. It installs essential packages like **Sway**, **dbus**, and other utilities to set up a Wayland session.

## Features

- Installs the necessary Wayland components, including:
  - **seatd** for seat management
  - **Sway** tiling window manager
  - **libinput**, **wlroots**, **xwayland**, and other essential packages
- Prompts the user to select a screen resolution from:
  - 1366 x 768
  - 1920 x 1080
  - 2560 x 1440
  - 3840 x 2160
- Optionally installs additional Wayland-compatible tools like:
  - **Alacritty** terminal
  - **foot** terminal
  - **swaylock** screen locker
  - **noto** fonts
  - **grim** (screenshot tool) and **slurp** (selection tool)
- Automatically adds the specified user to the `seatd` group
- Configures environment variables for Wayland

## Requirements

- FreeBSD, GhostBSD, or PolarisBSD system with internet access
- **jq** is required for monitor detection and handling screen resolutions (included in the installation script)
- Root privileges to execute the script

## Usage

### 1. Download the Script

Save the script as `install_wayland.sh`:

```sh
fetch https://github.com/vimanuelt/wayland-installation/install_wayland.sh
