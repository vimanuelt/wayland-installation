#!/bin/sh

# Exit immediately if a command exits with a non-zero status
set -e

# Verbose mode (default: enabled)
VERBOSE=1

# Log file for debugging
LOG_FILE="/var/log/install_wayland.log"
exec > "$LOG_FILE" 2>&1

# Function for logging
log() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$1"
  fi
}

# Function to detect the system's keyboard layout from rc.conf
detect_keyboard_layout() {
  log "Detecting system keyboard layout..."
  
  # Detect keyboard layout from /etc/rc.conf
  if grep -q "keymap=" /etc/rc.conf; then
    KEYMAP=$(grep "keymap=" /etc/rc.conf | cut -d'"' -f2)
    log "Detected keyboard layout: $KEYMAP"
  else
    log "No keyboard layout detected, defaulting to 'us'"
    KEYMAP="us"
  fi
}

# Function to install necessary packages
install_packages() {
  log "Installing Wayland, seatd, Sway, and dependencies..."

  # Essential packages for Wayland and Sway
  ESSENTIAL_PACKAGES="wayland seatd sway libinput wlroots xwayland"

  for pkg in $ESSENTIAL_PACKAGES; do
    if ! pkg info "$pkg" >/dev/null 2>&1; then
      log "Installing $pkg..."
      if ! pkg install -y "$pkg"; then
        log "Error installing $pkg"
        exit 1
      fi
    else
      log "$pkg is already installed."
    fi
  done

  log "All required packages are installed."
}

# Ensure seatd and dbus services are enabled and running
enable_services() {
  log "Enabling seatd and dbus services..."

  # Enable seatd and dbus on startup
  sysrc seatd_enable="YES" || { log "Failed to enable seatd"; exit 1; }
  sysrc dbus_enable="YES" || { log "Failed to enable dbus"; exit 1; }

  # Start seatd and dbus if not already running
  if service seatd status >/dev/null 2>&1; then
    log "seatd is already running, continuing..."
  else
    log "Starting seatd service..."
    if ! service seatd start; then
      log "Failed to start seatd"
      exit 1
    fi
  fi

  if service dbus status >/dev/null 2>&1; then
    log "dbus is already running, continuing..."
  else
    log "Starting dbus service..."
    if ! service dbus start; then
      log "Failed to start dbus"
      exit 1
    fi
  fi

  log "Services enabled and running."
}

# Ensure the sway.desktop file exists and is correctly configured
ensure_sway_desktop() {
  log "Checking sway.desktop for LightDM..."
  SWAY_DESKTOP_FILE="/usr/local/share/xsessions/sway.desktop"
  
  if [ ! -f "$SWAY_DESKTOP_FILE" ]; then
    log "Creating sway.desktop for LightDM"
    cat <<EOF > "$SWAY_DESKTOP_FILE"
[Desktop Entry]
Name=Sway
Comment=An i3-compatible Wayland window manager
Exec=/usr/local/bin/sway
TryExec=/usr/local/bin/sway
Type=Application
DesktopNames=Sway
EOF
  else
    log "sway.desktop already exists."
  fi
}

# Ensure LightDM is configured to launch Sway and not X11
configure_lightdm() {
  log "Configuring LightDM to use Sway and disable X11..."

  LIGHTDM_CONF="/usr/local/etc/lightdm/lightdm.conf"
  
  # Ensure session-wrapper is set, default user session is Sway, and X is disabled
  sed -i '' -e 's/^#session-wrapper=.*/session-wrapper=\/usr\/local\/etc\/lightdm\/Xsession/' \
            -e 's/^user-session=.*/user-session=sway/' \
            -e 's/^#xserver-command=X/#xserver-command=X/' \
            "$LIGHTDM_CONF"
  
  log "LightDM configured to use Sway."
}

# Ensure XDG_SESSION_TYPE and XDG_RUNTIME_DIR are set for Wayland
ensure_wayland_environment() {
  log "Ensuring Wayland environment variables are set..."

  # Set environment variables globally in /etc/profile
  if ! grep -q "XDG_SESSION_TYPE=wayland" /etc/profile; then
    log "Adding XDG_SESSION_TYPE to /etc/profile"
    echo 'export XDG_SESSION_TYPE=wayland' >> /etc/profile
  fi

  if ! grep -q "XDG_RUNTIME_DIR" /etc/profile; then
    log "Adding XDG_RUNTIME_DIR to /etc/profile"
    echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> /etc/profile
  fi

  log "Wayland environment variables set."
}

# Ensure Xsession script launches Sway when selected
configure_xsession() {
  log "Configuring Xsession script for Sway..."

  XSESSION_SCRIPT="/usr/local/etc/lightdm/Xsession"

  # Check if Sway is configured to launch in Xsession script
  if ! grep -q "exec sway" "$XSESSION_SCRIPT"; then
    log "Adding Sway startup configuration to Xsession script"
    cat <<'EOF' >> "$XSESSION_SCRIPT"

# Ensure XDG_RUNTIME_DIR is set
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 0700 "$XDG_RUNTIME_DIR"
    fi
fi

# Start Sway session
if [ "$1" = "sway" ]; then
    exec sway
fi
EOF
  else
    log "Sway is already configured in Xsession script."
  fi
}

# Configure Sway to use the detected system keyboard layout
configure_sway_input() {
  log "Configuring Sway input devices with system keyboard layout..."
  
  # Create the Sway config file if it doesn't exist
  SWAY_CONFIG_DIR="$HOME/.config/sway"
  SWAY_CONFIG_FILE="$SWAY_CONFIG_DIR/config"
  mkdir -p "$SWAY_CONFIG_DIR"

  # Add keyboard layout to Sway config
  cat <<EOF > "$SWAY_CONFIG_FILE"
# Sway configuration file

# Input configuration
input "type:keyboard" {
    xkb_layout $KEYMAP
}
EOF

  log "Sway configured with keyboard layout: $KEYMAP"
}

# Restart LightDM to apply changes
restart_lightdm() {
  log "Restarting LightDM to apply changes..."
  if ! service lightdm restart; then
    log "Failed to restart LightDM"
    exit 1
  fi
}

# Reboot the system after the script completes
reboot_system() {
  log "Rebooting the system to apply changes..."
  if ! reboot; then
    log "Failed to reboot the system"
    exit 1
  fi
}

# Main script logic
main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root: sudo sh $0"
    exit 1
  fi

  log "Starting installation of Wayland, seatd, and Sway..."

  # Detect the system's current keyboard layout
  detect_keyboard_layout

  # Install Wayland, seatd, Sway, and other essential packages
  install_packages

  # Enable seatd and dbus services
  enable_services

  # Configure necessary components for LightDM and Sway
  ensure_sway_desktop
  configure_lightdm
  ensure_wayland_environment
  configure_xsession

  # Configure Sway to use the system keyboard layout
  configure_sway_input

  # Restart LightDM to apply the changes
  restart_lightdm

  # Reboot the system to apply all changes
  reboot_system

  log "Installation and configuration complete!"
}

main "$@"
