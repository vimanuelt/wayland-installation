#!/bin/sh

# Exit immediately if a command exits with a non-zero status
set -e

# Verbose mode (default: enabled)
VERBOSE=1

# Function for logging
log() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$1"
  fi
}

# Ensure XDG_RUNTIME_DIR is set for the current user
ensure_xdg_runtime_dir() {
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"  # Use id -u to get the UID of the current user
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
      log "Creating XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 0700 "$XDG_RUNTIME_DIR"
    fi
  else
    log "XDG_RUNTIME_DIR is already set to $XDG_RUNTIME_DIR"
  fi

  # Ensure XDG_RUNTIME_DIR is set in /etc/profile globally
  if ! grep -q "XDG_RUNTIME_DIR" /etc/profile; then
    log "Adding XDG_RUNTIME_DIR to /etc/profile for all users"
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /etc/profile
  else
    log "XDG_RUNTIME_DIR is already present in /etc/profile"
  fi
}

# Function to ensure seatd socket permissions are correct
ensure_seatd_socket_permissions() {
  SEATD_SOCKET="/var/run/seatd.sock"
  
  if [ -e "$SEATD_SOCKET" ]; then
    log "Checking seatd socket permissions..."
    
    # Change ownership to root:seatd if it's not already set
    if [ "$(stat -c %G "$SEATD_SOCKET")" != "seatd" ]; then
      log "Changing group of $SEATD_SOCKET to seatd"
      sudo chown root:seatd "$SEATD_SOCKET"
    fi
    
    # Ensure correct permissions (660)
    if [ "$(stat -c %a "$SEATD_SOCKET")" != "660" ]; then
      log "Setting permissions to 660 for $SEATD_SOCKET"
      sudo chmod 660 "$SEATD_SOCKET"
    fi
  else
    log "seatd socket $SEATD_SOCKET not found. Please check if seatd is running."
  fi
}

# Cleanup function
rollback() {
  log "Rolling back changes..."
  if [ -n "$PACKAGES_INSTALLED" ]; then
    pkg delete -y $PACKAGES_INSTALLED
  fi
}

# Function to install packages
install_packages() {
  log "Installing essential packages..."
  pkg update -f || exit 1

  for pkg in $ESSENTIAL_PACKAGES; do
    if ! pkg info "$pkg" >/dev/null 2>&1; then
      pkg install -y "$pkg" || exit 1
    else
      log "$pkg is already installed."
    fi
  done

  if [ "$INSTALL_OPTIONAL" = "y" ]; then
    for pkg in $OPTIONAL_PACKAGES; do
      if ! pkg info "$pkg" >/dev/null 2>&1; then
        pkg install -y "$pkg" || log "Failed to install $pkg, continuing..."
      else
        log "$pkg is already installed."
      fi
    done
  fi
}

# Function to enable and start services, with rc.conf entry check
enable_service() {
  local service_name=$1
  local service_entry="${service_name}_enable"

  if grep -q "^${service_entry}=" /etc/rc.conf; then
    log "$service_name already enabled in /etc/rc.conf."
  else
    sysrc "${service_entry}=YES" || exit 1
  fi

  if service "$service_name" status >/dev/null 2>&1; then
    log "$service_name is already running."
  else
    service "$service_name" start || log "Failed to start $service_name, continuing..."
  fi
}

# Function to create the seatd group if it doesn't exist
create_seatd_group() {
  if ! getent group seatd >/dev/null; then
    log "Creating seatd group..."
    if ! pw groupadd seatd; then
      echo "Failed to create seatd group. Exiting."
      exit 1
    fi
  else
    log "seatd group already exists."
  fi
}

# Prompt for the username if not set
if [ -z "$USERNAME" ]; then
  read -p "Enter the username to configure: " USERNAME
fi

# Verify the user exists
if ! id "$USERNAME" >/dev/null 2>&1; then
  echo "User $USERNAME does not exist. Exiting."
  exit 1
fi

# Set the user's home directory
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)

# Check if the home directory exists, exit if not found
if [ ! -d "$USER_HOME" ]; then
  echo "User home directory $USER_HOME does not exist. Exiting."
  exit 1
fi

# Determine the user's default shell and set the profile file accordingly
USER_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)

case "$USER_SHELL" in
  */bash)
    PROFILE_FILE="$USER_HOME/.bash_profile"
    ;;
  */zsh)
    PROFILE_FILE="$USER_HOME/.zprofile"
    ;;
  */fish)
    PROFILE_FILE="$USER_HOME/.config/fish/config.fish"
    ;;
  *)
    PROFILE_FILE="$USER_HOME/.profile"
    ;;
esac

log "Using profile file: $PROFILE_FILE"

# Function to add user to the seatd group
add_user_to_seatd() {
  if id -nG "$USERNAME" | grep -qw "seatd"; then
    log "$USERNAME is already a member of seatd group."
  else
    log "Adding $USERNAME to seatd group..."
    if ! pw groupmod seatd -m "$USERNAME"; then
      echo "Failed to add $USERNAME to seatd group. Exiting."
      exit 1
    fi
  fi
}

# Function to configure environment variables, including XDG_RUNTIME_DIR
configure_environment() {
  log "Configuring environment variables in $PROFILE_FILE..."

  # Check if the profile file exists; create it if necessary
  if [ ! -f "$PROFILE_FILE" ]; then
    log "Profile file $PROFILE_FILE does not exist. Creating it."
    if ! touch "$PROFILE_FILE"; then
      echo "Failed to create $PROFILE_FILE. Exiting."
      exit 1
    fi
    chown "$USERNAME":"$USERNAME" "$PROFILE_FILE"
  fi

  # Backup existing profile file
  if ! cp "$PROFILE_FILE" "$PROFILE_FILE.bak.$(date +%F_%T)"; then
    echo "Failed to backup $PROFILE_FILE. Exiting."
    exit 1
  fi

  # Append environment variables
  cat <<EOF >> "$PROFILE_FILE"

# Wayland environment variables added on $(date)
export XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export MOZ_ENABLE_WAYLAND=1    # For Firefox
export QT_QPA_PLATFORM=wayland # For Qt applications
EOF

  # Set ownership of the profile file
  if ! chown "$USERNAME":"$USERNAME" "$PROFILE_FILE"; then
    echo "Failed to set ownership of $PROFILE_FILE. Exiting."
    exit 1
  fi
}

# Main script logic
main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root: sudo sh $0"
    exit 1
  fi

  log "Starting installation of Wayland environment with seatd..."

  # Check if pkg is installed
  command -v pkg >/dev/null 2>&1 || { echo "pkg is not installed. Please install pkg first."; exit 1; }

  # Ensure XDG_RUNTIME_DIR is set globally
  ensure_xdg_runtime_dir

  # Install packages, enable services, and configure environment
  install_packages
  enable_service "seatd"
  enable_service "dbus"

  # Set up environment for the specific user
  add_user_to_seatd
  configure_environment

  # Ensure seatd socket permissions are correct
  ensure_seatd_socket_permissions

  log "Installation and configuration complete!"
}

# Execute the main function
main "$@"
