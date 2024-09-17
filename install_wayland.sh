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

# Ensure XDG_RUNTIME_DIR is set globally for all sessions
ensure_xdg_runtime_dir() {
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
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

# Create or update sway.desktop file
configure_sway_desktop() {
  log "Creating or updating sway.desktop for LightDM"
  cat <<EOF > /usr/local/share/xsessions/sway.desktop
[Desktop Entry]
Name=Sway
Comment=An i3-compatible Wayland window manager
Exec=/usr/local/bin/sway
TryExec=/usr/local/bin/sway
Type=Application
DesktopNames=Sway
EOF
}

# Modify lightdm.conf to support Sway
configure_lightdm() {
  log "Configuring LightDM to support Sway"
  
  LIGHTDM_CONF="/usr/local/etc/lightdm/lightdm.conf"
  
  # Ensure session-wrapper is set and default user session is flexible
  sed -i '' -e 's/^#session-wrapper=.*/session-wrapper=\/usr\/local\/etc\/lightdm\/Xsession/' \
            -e 's/^user-session=.*/user-session=default/' \
            "$LIGHTDM_CONF"
}

# Update Xsession script for XDG_RUNTIME_DIR and Sway session
configure_xsession() {
  log "Configuring Xsession script for Sway"
  
  XSESSION_SCRIPT="/usr/local/etc/lightdm/Xsession"
  
  # Add XDG_RUNTIME_DIR and Sway startup handling
  if ! grep -q "XDG_RUNTIME_DIR" "$XSESSION_SCRIPT"; then
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
  fi
}

# Restart LightDM to apply changes
restart_lightdm() {
  log "Restarting LightDM to apply changes"
  service lightdm restart
}

# Main script logic
main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root: sudo sh $0"
    exit 1
  fi

  log "Starting installation of Wayland environment with seatd and configuring LightDM for Sway..."

  # Install packages, configure Sway session, and update LightDM and Xsession
  install_packages
  configure_sway_desktop
  configure_lightdm
  configure_xsession

  # Restart LightDM
  restart_lightdm

  log "Installation and configuration complete!"
}

main "$@"
