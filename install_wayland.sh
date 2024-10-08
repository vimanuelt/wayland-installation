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

# Function to prompt the user to select a screen resolution
prompt_resolution_selection() {
  log "Prompting user to select screen resolution..."

  # Output prompt directly to the terminal and read input
  printf "\nPlease select your preferred screen resolution:\n" > /dev/tty
  printf "1) 1366 x 768\n" > /dev/tty
  printf "2) 1920 x 1080\n" > /dev/tty
  printf "3) 2560 x 1440\n" > /dev/tty
  printf "4) 3840 x 2160\n" > /dev/tty

  # Read user input from the terminal
  read -p "Enter the number corresponding to your selection (1-4): " resolution_choice < /dev/tty

  case "$resolution_choice" in
    1) SCREEN_RESOLUTION="1366x768";;
    2) SCREEN_RESOLUTION="1920x1080";;
    3) SCREEN_RESOLUTION="2560x1440";;
    4) SCREEN_RESOLUTION="3840x2160";;
    *) 
      printf "Invalid selection. Defaulting to 1366x768.\n" > /dev/tty
      SCREEN_RESOLUTION="1366x768"
    ;;
  esac

  log "Selected resolution: $SCREEN_RESOLUTION"
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

  # Get the username of the user who invoked the script
  USERNAME=$(logname 2>/dev/null || echo "$SUDO_USER")
  
  if [ -z "$USERNAME" ]; then
    log "Failed to detect the non-root user. Exiting."
    exit 1
  fi

  # Get the home directory of the non-root user
  USER_HOME=$(eval echo "~$USERNAME")

  log "Detected user: $USERNAME, home directory: $USER_HOME"
}

# Function to install necessary packages
install_packages() {
  log "Installing Wayland, seatd, Sway, and dependencies..."

  # Essential packages for Wayland and Sway
  ESSENTIAL_PACKAGES="wayland seatd sway libinput wlroots xwayland foot grim wofi jq"

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

# Ensure the user is in the seatd group and manage input device permissions
configure_input_permissions() {
  log "Configuring input permissions..."

  # Add the user to the seatd group
  log "Adding $USERNAME to the seatd group..."
  pw groupmod seatd -m "$USERNAME"

  # Manually adjust the permissions of the input devices
  log "Setting proper permissions on input devices..."
  chgrp seatd /dev/input/event* || { log "Failed to change group of input devices"; exit 1; }
  chmod g+rw /dev/input/event* || { log "Failed to set group read/write permissions on input devices"; exit 1; }

  # Create a devd rule to automatically set permissions for future input devices
  log "Creating devd rule for input devices..."
  cat <<EOF > /etc/devd/seatd-input.conf
attach 100 {
    device-name "input/event";
    action "chgrp seatd /dev/input/event*; chmod g+rw /dev/input/event*";
};
EOF

  # Restart devd to apply the rule
  log "Restarting devd to apply new rule..."
  service devd restart || { log "Failed to restart devd"; exit 1; }

  log "Input permissions configured successfully."
}

# Function to set up the toggle_seatd.sh script
setup_toggle_seatd_script() {
  log "Setting up the toggle_seatd.sh script..."

  cat <<EOF > /usr/local/bin/toggle_seatd.sh
#!/bin/sh

if [ "\$1" = "wayland" ]; then
    echo "Enabling seatd devd rule for Wayland..."
    sudo sed -i '' 's/^#//g' /etc/devd/seatd-input.conf
    sudo service devd restart
    sudo service seatd start
elif [ "\$1" = "x" ]; then
    echo "Disabling seatd devd rule for X Window..."
    sudo sed -i '' 's/^\(.*\)/#\1/g' /etc/devd/seatd-input.conf
    sudo service devd restart
    sudo service seatd stop
else
    echo "Usage: toggle_seatd.sh {wayland|x}"
fi
EOF

  # Make the script executable
  chmod +x /usr/local/bin/toggle_seatd.sh

  log "toggle_seatd.sh script has been set up successfully."
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
    if [ ! -d "$XDG_RUNTIME_DIR"; then
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

# Copy the default Sway config from /usr/local/etc/sway/config to both root's and non-root user's ~/.config/sway
copy_default_sway_config() {
  log "Copying default Sway configuration..."

  # Create the Sway config directory in root's home
  SWAY_CONFIG_DIR="/root/.config/sway"
  mkdir -p "$SWAY_CONFIG_DIR"

  # Copy the default Sway configuration to root's home
  if cp /usr/local/etc/sway/config "$SWAY_CONFIG_DIR/"; then
    log "Copied default Sway configuration to /root/.config/sway"
  else
    log "Failed to copy default Sway configuration to /root/.config/sway"
    exit 1
  fi

  # Now copy the config to the non-root user's home
  SWAY_USER_CONFIG_DIR="$USER_HOME/.config/sway"
  mkdir -p "$SWAY_USER_CONFIG_DIR"

  if cp /usr/local/etc/sway/config "$SWAY_USER_CONFIG_DIR/"; then
    log "Copied default Sway configuration to $USER_HOME/.config/sway"
  else
    log "Failed to copy default Sway configuration to $USER_HOME/.config/sway"
    exit 1
  fi

  # Append keyboard configuration, selected resolution, and remove swaynag exit prompt
  cat <<EOF >> "$SWAY_CONFIG_DIR/config"
# Keyboard configuration
input "type:keyboard" {
    xkb_layout us
    repeat_delay 500
    repeat_rate 30
}

# Set screen resolution to $SCREEN_RESOLUTION
output * resolution $SCREEN_RESOLUTION scale 1.0

# Keybinding to exit Sway (Mod + Shift + e)
# Remove the default swaynag exit prompt and replace with direct exit
unbindsym \$mod+Shift+e
bindsym \$mod+Shift+e exec "swaymsg exit"

# Detect and configure monitors
exec_always --no-startup-id ~/.config/sway/monitor_detect.sh
EOF

  cat <<EOF >> "$SWAY_USER_CONFIG_DIR/config"
# Keyboard configuration
input "type:keyboard" {
    xkb_layout us
    repeat_delay 500
    repeat_rate 30
}

# Set screen resolution to $SCREEN_RESOLUTION
output * resolution $SCREEN_RESOLUTION scale 1.0

# Keybinding to exit Sway (Mod + Shift + e)
# Remove the default swaynag exit prompt and replace with direct exit
unbindsym \$mod+Shift+e
bindsym \$mod+Shift+e exec "swaymsg exit"

# Detect and configure monitors
exec_always --no-startup-id ~/.config/sway/monitor_detect.sh
EOF

  # Create the monitor detection script
  cat <<'EOF' > "$SWAY_USER_CONFIG_DIR/monitor_detect.sh"
#!/bin/sh

# Retry mechanism in case swaymsg fails to connect
RETRIES=5
DELAY=1

for i in $(seq 1 $RETRIES); do
    # Try to get the output information
    OUTPUT_INFO=$(swaymsg -t get_outputs 2>/dev/null)
    if [ $? -eq 0 ]; then
        # swaymsg succeeded, proceed to configure the monitor
        echo "$OUTPUT_INFO" | jq -r '.[] | select(.active == true) | .name' | while read -r MONITOR_NAME; do
            echo "Detecting monitor: $MONITOR_NAME"

            # Extract available modes (resolutions) for the monitor
            AVAILABLE_MODES=$(echo "$OUTPUT_INFO" | jq -r --arg MONITOR "$MONITOR_NAME" '.[] | select(.name == $MONITOR) | .modes[] | "\(.width)x\(.height)"')

            # Find the largest resolution available
            LARGEST_RES=$(echo "$AVAILABLE_MODES" | sort -nr | head -n 1)

            if [ -n "$LARGEST_RES" ]; then
                echo "Setting monitor $MONITOR_NAME to the largest resolution: $LARGEST_RES"
                swaymsg output "$MONITOR_NAME" resolution "$LARGEST_RES" scale 1.0
            else
                echo "No resolutions found for monitor $MONITOR_NAME"
            fi
        done
        exit 0
    else
        echo "swaymsg failed, retrying in $DELAY seconds... (Attempt $i/$RETRIES)"
        sleep $DELAY
    fi
done

echo "Failed to connect to sway after $RETRIES attempts."
exit 1
EOF

  # Make the monitor detect script executable
  chmod +x "$SWAY_USER_CONFIG_DIR/monitor_detect.sh"
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

  # Prompt the user to select their preferred resolution
  prompt_resolution_selection

  # Install Wayland, seatd, Sway, and other essential packages
  install_packages

  # Configure input permissions
  configure_input_permissions

  # Set up toggle_seatd.sh script for switching between Wayland and X
  setup_toggle_seatd_script

  # Enable seatd, dbus, and LightDM services to start on boot
  enable_services_on_boot

  # Configure necessary components for LightDM and Sway
  ensure_sway_desktop
  configure_lightdm
  ensure_wayland_environment
  configure_xsession

  # Copy the default Sway configuration to both root's and non-root user's home directories
  copy_default_sway_config

  # Reboot the system to apply all changes
  reboot_system

  log "Installation and configuration complete!"
}

main "$@"
