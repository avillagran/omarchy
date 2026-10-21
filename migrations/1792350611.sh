echo "Install Omarchy's Quickshell build so plugins keep the theme palette on Qt 6.12"

# Qt 6.12 adds a QtQuick Color singleton that shadows the qs.Commons Color.
# Only Omarchy's Quickshell build honors `//@ pragma OmarchyLoadPatch`, which
# pins QtQuick imports to 6.11 for the shell and every plugin it loads. ARM
# keeps [omarchy] at `Usage = Sync`, so an unqualified quickshell, including
# 1787399318's reinstall, resolves to Arch's build. The update helper now
# selects omarchy/quickshell, but this update still ran the previous helper.
version=$(quickshell --version 2>/dev/null || true)

if [[ $version != *"distributed by Omarchy"* ]]; then
  # Skip instead of failing when [omarchy] cannot serve it: a failed migration
  # aborts omarchy-migrate's whole run and retries at every login.
  if ! pacman -Si omarchy/quickshell &>/dev/null; then
    echo "omarchy/quickshell is not in any configured repo; keeping the current quickshell" >&2
    exit 0
  fi

  # --ask 4 lets pacman replace a conflicting quickshell-git in place.
  sudo pacman -S --noconfirm --ask 4 omarchy/quickshell
fi
