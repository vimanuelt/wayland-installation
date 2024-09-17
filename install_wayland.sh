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

# Function to detect the home directory of the non-root user
get_user_home_directory() {
  log "Detecting non-root user's home directory..."

  # Get the username of the user running the script (who invoked sudo)
  USERNAME=$(logname)
  USER_HOME=$(eval echo "~$USERNAME")

  log "Detected user: $USERNAME, home directory: $USER_HOME"
}

# Function to install necessary packages
install_packages() {
  log "Installing Wayland, seatd, Sway, and dependencies..."

  # Essential packages for Wayland and Sway
  ESSENTIAL_PACKAGES="wayland seatd sway libinput wlroots xwayland foot grim wofi swaynag"

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

# Enable seatd, dbus, and LightDM services to start on boot, but do not start them immediately
enable_services_on_boot() {
  log "Enabling seatd, dbus, and LightDM services to start on boot..."

  # Enable seatd, dbus, and LightDM on startup
  sysrc seatd_enable="YES" || { log "Failed to enable seatd"; exit 1; }
  sysrc dbus_enable="YES" || { log "Failed to enable dbus"; exit 1; }
  sysrc lightdm_enable="YES" || { log "Failed to enable LightDM"; exit 1; }

  log "Services will start after reboot."
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

# Configure Sway with the provided configuration
configure_sway_input() {
  log "Configuring Sway with the provided configuration..."

  # Create the Sway config file in the user's home directory
  SWAY_CONFIG_DIR="$USER_HOME/.config/sway"
  SWAY_CONFIG_FILE="$SWAY_CONFIG_DIR/config"
  mkdir -p "$SWAY_CONFIG_DIR"

  # Add the provided Sway configuration file
  cat <<EOF > "$SWAY_CONFIG_FILE"
# Default config for sway

### Variables
set \$mod Mod4  # Use Mod4 (Super/Windows key) as the modifier key
set \$left h
set \$down j
set \$up k
set \$right l
set \$term foot  # Terminal emulator
set \$menu wofi  # Application launcher

### Output configuration
output * bg /usr/local/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png fill

### Key bindings
# Basics
bindsym \$mod+Return exec \$term  # Open terminal
bindsym \$mod+Shift+q kill  # Close focused window
bindsym \$mod+d exec \$menu  # Open application launcher
floating_modifier \$mod normal  # Drag floating windows with mod + mouse buttons
bindsym \$mod+Shift+c reload  # Reload config
bindsym \$mod+Shift+e exec swaynag -t warning -m 'Exit sway?' -B 'Yes' 'swaymsg exit'  # Exit sway

# Navigation
bindsym \$mod+\$left focus left
bindsym \$mod+\$down focus down
bindsym \$mod+\$up focus up
bindsym \$mod+\$right focus right
bindsym \$mod+Shift+\$left move left
bindsym \$mod+Shift+\$down move down
bindsym \$mod+Shift+\$up move up
bindsym \$mod+Shift+\$right move right

# Workspaces
bindsym \$mod+{1-10} workspace number {1-10}
bindsym \$mod+Shift+{1-10} move container to workspace number {1-10}

# Layout
bindsym \$mod+b splith
bindsym \$mod+v splitv
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split
bindsym \$mod+f fullscreen
bindsym \$mod+Shift+space floating toggle
bindsym \$mod+space focus mode_toggle
bindsym \$mod+a focus parent

# Scratchpad
bindsym \$mod+Shift+minus move scratchpad
bindsym \$mod+minus scratchpad show

# Resizing
mode "resize" {
    bindsym \$left resize shrink width 10px
    bindsym \$down resize grow height 10px
    bindsym \$up resize shrink height 10px
    bindsym \$right resize grow width 10px
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym \$mod+r mode "resize"

# Utilities
bindsym Print exec grim  # Screenshot

# Status Bar
bar {
    position top
    status_command while date +'%Y-%m-%d %X'; do sleep 1; done
    colors {
        statusline #ffffff
        background #323232
        inactive_workspace #32323200 #32323200 #5c5c5c
    }
}

include /usr/local/etc/sway/config.d/*
EOF

  log "Sway configured with the provided configuration."
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

  # Detect the non-root user's home directory
  get_user_home_directory

  # Install Wayland, seatd, Sway, and other essential packages
  install_packages

  # Enable seatd, dbus, and LightDM services to start on boot
  enable_services_on_boot

  # Configure necessary components for LightDM and Sway
  ensure_sway_desktop
  configure_lightdm
  ensure_wayland_environment
  configure_xsession

  # Configure Sway with the provided configuration file
  configure_sway_input

  # Reboot the system to apply all changes
  reboot_system

  log "Installation and configuration complete!"
}

main "$@"
