#!/usr/bin/env sh
# install-requirements.sh — installs build requirements for hedera-tss-ceremony-helper.
#
# Currently installs:
#   - podman
#   - qemu-user-static (Linux only, required for cross-platform builds)
#
# Usage:
#   ./scripts/install-requirements.sh
#
set -eu

install_podman() {
  echo "Installing Podman..."
  OS="$(uname -s)"
  case "${OS}" in
    Darwin)
      if ! command -v brew > /dev/null 2>&1; then
        echo "ERROR: Homebrew is required to install Podman on macOS." >&2
        echo "Install Homebrew from https://brew.sh, then re-run this script." >&2
        exit 1
      fi
      brew install podman
      podman machine init || true
      podman machine start || true
      ;;
    Linux)
      if command -v apt-get > /dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y podman
      elif command -v dnf > /dev/null 2>&1; then
        sudo dnf install -y podman
      elif command -v yum > /dev/null 2>&1; then
        sudo yum install -y podman
      elif command -v zypper > /dev/null 2>&1; then
        sudo zypper install -y podman
      elif command -v pacman > /dev/null 2>&1; then
        sudo pacman -Sy --noconfirm podman
      else
        echo "ERROR: unsupported Linux distribution — install Podman manually." >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: unsupported OS '${OS}' — install Podman manually." >&2
      exit 1
      ;;
  esac
  echo "Podman installed: $(podman --version)"
}

# Install QEMU user-mode static binaries for cross-platform container builds.
# On macOS this is handled automatically by the Podman VM; on Linux it must be
# installed explicitly so binfmt_misc can run foreign-arch binaries.
install_qemu_user_static() {
  echo "Installing qemu-user-static for cross-platform builds..."
  if command -v apt-get > /dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y qemu-user-static
  elif command -v dnf > /dev/null 2>&1; then
    sudo dnf install -y qemu-user-static
  elif command -v yum > /dev/null 2>&1; then
    sudo yum install -y qemu-user-static
  elif command -v zypper > /dev/null 2>&1; then
    sudo zypper install -y qemu-linux-user
  elif command -v pacman > /dev/null 2>&1; then
    sudo pacman -Sy --noconfirm qemu-user-static
  else
    echo "WARNING: could not install qemu-user-static — cross-platform builds may fail." >&2
  fi
}

# ── check & install each requirement ─────────────────────────────────────────
if command -v podman > /dev/null 2>&1; then
  echo "podman already installed: $(podman --version)"
else
  install_podman
fi

if [ "$(uname -s)" = "Linux" ]; then
  if [ -d /proc/sys/fs/binfmt_misc ] && ls /proc/sys/fs/binfmt_misc/qemu-* > /dev/null 2>&1; then
    echo "qemu-user-static already configured"
  else
    install_qemu_user_static
  fi
fi

echo ""
echo "All requirements satisfied."
