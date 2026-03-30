#!/usr/bin/env sh
# install-requirements.sh — installs build requirements for hedera-tss-ceremony-helper.
#
# Currently installs:
#   - podman
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

# ── check & install each requirement ─────────────────────────────────────────
if command -v podman > /dev/null 2>&1; then
  echo "podman already installed: $(podman --version)"
else
  install_podman
fi

echo ""
echo "All requirements satisfied."
