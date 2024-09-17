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

# Cleanup function
rollback() {
  log "Rolling back changes..."
  # Uninstall installed packages if rollback occurs
  if [ -n "$PACKAGES_INSTALLED" ]; then
    pkg delete -y $PACKAGES_INSTALLED
  fi
  # Restore any backed-up configuration files if necessary
}

# Function to check if a package is installed
check_installed() {
  if pkg info "$1" >/dev/null 2>&1; then
    log "$1 is already installed."
    return 0
  else
    return 1
  fi
}

# Function to install packages
install_packages() {
  log "Installing essential packages..."
  if ! pkg update -f; then
    echo "Failed to update package repository. Exiting."
    exit 1
  fi

  for pkg in $ESSENTIAL_PACKAGES; do
    if ! check_installed "$pkg"; then
      if ! pkg install -y "$pkg"; then
        echo "Failed to install $pkg. Exiting."
        exit 1
      fi
      PACKAGES_INSTALLED="$PACKAGES_INSTALLED $pkg"
    fi
  done

  if [ "$INSTALL_OPTIONAL" = "y" ]; then
    log "Installing optional packages..."
    for pkg in $OPTIONAL_PACKAGES; do
      if ! check_installed "$pkg"; then
        if ! pkg install -y "$pkg"; then
          echo "Failed to install $pkg. Skipping."
        else
          PACKAGES_INSTALLED="$PACKAGES_INSTALLED $pkg"
        fi
      fi
    done
  else
    log "Skipping optional package installation."
  fi
}

# Function to enable and start services, with rc.conf entry check
enable_service() {
  local service_name=$1
  local service_entry="${service_name}_enable"
  
  # Check if the service entry already exists in /etc/rc.conf
  if grep -q "^${service_entry}=" /etc/rc.conf; then
    log "$service_name already enabled in /etc/rc.conf."
  else
    log "Enabling $service_name service in /etc/rc.conf..."
    if ! sysrc "${service_entry}=YES"; then
      echo "Failed to enable $service_name service. Exiting."
      exit 1
    fi
  fi

  # Check if the service is already running
  if service "$service_name" status >/dev/null 2>&1; then
    log "$service_name is already running."
  else
    # Start the service if it's not running
    log "Starting $service_name service..."
    if ! service "$service_name" start; then
      echo "Failed to start $service_name service. Continuing."
    fi
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

  # Check if the user's home directory exists
  if [ ! -d "$USER_HOME" ]; then
    echo "User home directory $USER_HOME does not exist. Exiting."
    exit 1
  fi

  # Create the profile file if it doesn't exist
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

  # Set XDG_RUNTIME_DIR and ensure it exists
  log "Setting XDG_RUNTIME_DIR..."
  RUNTIME_DIR="/run/user/$(id -u $USERNAME)"
  if [ ! -d "$RUNTIME_DIR" ]; then
    log "Creating runtime directory $RUNTIME_DIR..."
    mkdir -p "$RUNTIME_DIR"
    chown "$USERNAME":"$USERNAME" "$RUNTIME_DIR"
    chmod 0700 "$RUNTIME_DIR"
  fi

  # Append environment variables
  cat <<EOF >> "$PROFILE_FILE"

# Wayland environment variables added on $(date)
export XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR=$RUNTIME_DIR
export MOZ_ENABLE_WAYLAND=1    # For Firefox
export QT_QPA_PLATFORM=wayland # For Qt applications
EOF

  # Set ownership of the profile file
  if ! chown "$USERNAME":"$USERNAME" "$PROFILE_FILE"; then
    echo "Failed to set ownership of $PROFILE_FILE. Exiting."
    exit 1
  fi
}

# Main script
main() {
  # This script must be run as root
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root: sudo sh $0"
    exit 1
  fi

  log "Starting installation of Wayland environment with seatd..."

  # Check if pkg is installed
  if ! command -v pkg >/dev/null 2>&1; then
    echo "pkg is not installed. Please install pkg first."
    exit 1
  fi

  # Check for internet connection
  if ! ping -c 1 freebsd.org >/dev/null 2>&1; then
    echo "No internet connection detected. Please ensure you have internet access."
    exit 1
  fi

  # Define the list of essential packages
  ESSENTIAL_PACKAGES="seatd wayland wayland-protocols sway libinput wlroots mesa-libs xwayland dbus"

  # Define the list of optional packages (with noto instead of noto-fonts)
  OPTIONAL_PACKAGES="alacritty foot swaylock swayidle grim slurp noto"

  # Ask the user if they want to install optional packages
  while true; do
    echo -n "Do you want to install optional packages (y/n)? "
    read INSTALL_OPTIONAL
    case $INSTALL_OPTIONAL in
      [Yy]* ) INSTALL_OPTIONAL="y"; break;;
      [Nn]* ) INSTALL_OPTIONAL="n"; break;;
      * ) echo "Please answer yes or no.";;
    esac
  done

  # Prompt for the username and validate it
  while true; do
    echo -n "Enter the username to add to the seatd group: "
    read USERNAME
    if id "$USERNAME" >/dev/null 2>&1; then
      break
    else
      echo "User $USERNAME does not exist. Please try again."
    fi
  done

  # Set the user home directory and profile file
  USER_HOME=$(eval echo "~$USERNAME")
  
  # Detect user's shell and set the correct profile file
  USER_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
  
  case "$USER_SHELL" in
    *bash*)
      PROFILE_FILE="$USER_HOME/.bash_profile"
      ;;
    *zsh*)
      PROFILE_FILE="$USER_HOME/.zprofile"
      ;;
    *)
      PROFILE_FILE="$USER_HOME/.profile"
      ;;
  esac

  # Create seatd group if it doesn't exist
  create_seatd_group

  # Install essential and optional packages
  install_packages

  # Enable and start seatd and dbus services (with rc.conf entry check)
  enable_service "seatd"
  enable_service "dbus"

  # Add the user to the seatd group
  add_user_to_seatd

  # Configure environment variables (including XDG_RUNTIME_DIR)
  configure_environment

  log "Installation and configuration complete!"

  echo "Please log out and log back in to apply group changes and environment variables."
  echo "To start the Wayland compositor, run 'sway' after logging in as $USERNAME."
}

# Execute main function
main "$@"
