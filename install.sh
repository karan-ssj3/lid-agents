#!/bin/bash
# Lid Agents installer.
#
#   curl -fsSL https://github.com/liam-machine/lid-agents/releases/latest/download/install.sh | bash
#
# Installs "Lid Agents.app" (menu bar app; replaces an existing copy where it is, otherwise
# ~/Applications), links the `agents` command into ~/.local/bin, adds one sudoers rule allowing
# exactly `pmset -a disablesleep 0|1`, opens the app at login, and starts it. Nothing else on
# the system changes. Re-run to upgrade. Pin a version with LID_AGENTS_VERSION=1.0.0; the app's
# Update item passes LID_AGENTS_APP (its own path). From a checkout, `./install.sh` uses build/.
set -euo pipefail

REPO="liam-machine/lid-agents"
VERSION="${LID_AGENTS_VERSION:-latest}"
BUNDLE_ID="io.github.liam-machine.lid-agents"
NAME="Lid Agents.app"
OLD_APP="$HOME/Applications/LidAgents.app"    # the name before 1.0.6
APP="${LID_AGENTS_APP:-}"
if [ -z "$APP" ]; then
  for candidate in "/Applications/$NAME" "$HOME/Applications/$NAME"; do
    if [ -d "$candidate" ]; then APP="$candidate"; break; fi
  done
fi
[ "$APP" = "$OLD_APP" ] && APP=""
APP="${APP:-$HOME/Applications/$NAME}"
BIN_DIR="$HOME/.local/bin"
LINK="$BIN_DIR/agents"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mlid-agents:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Lid Agents is for macOS only."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || die "Lid Agents needs macOS 13 (Ventura) or later."
pmset -g batt | grep -q 'InternalBattery' || echo "Note: no internal battery found. Lid Agents is meant for MacBooks."
id -Gn | tr ' ' '\n' | grep -qx admin || die "Your account must be an administrator: the lid setting needs one pmset rule in /etc/sudoers.d."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Get the app: a local build when run from a checkout, otherwise the GitHub release
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$self" ] && [ -d "$(dirname "$self")/build/$NAME" ]; then
  src="$(cd "$(dirname "$self")" && pwd)/build/$NAME"
  step "Using local build: $src"
else
  if [ "$VERSION" = "latest" ]; then
    url="https://github.com/$REPO/releases/latest/download/lid-agents.tar.gz"
  else
    url="https://github.com/$REPO/releases/download/v${VERSION#v}/lid-agents.tar.gz"
  fi
  step "Downloading $url"
  curl -fsSL "$url" -o "$tmp/lid-agents.tar.gz" || die "Download failed."
  tar -xzf "$tmp/lid-agents.tar.gz" -C "$tmp"
  src="$tmp/$NAME"
  [ -d "$src" ] || src="$tmp/LidAgents.app"     # releases before 1.0.6
fi
[ -x "$src/Contents/MacOS/LidAgents" ] || die "The download did not contain the Lid Agents app."

# 2. Install the app (quit a running copy first so the upgrade takes)
step "Installing $APP"
# -a: when the app's own Update item started this installer, the app is our ancestor,
# and macOS pkill skips ancestors by default. `open` below would then just reactivate it.
pkill -a -x LidAgents 2>/dev/null || true
for _ in $(seq 50); do pgrep -x LidAgents >/dev/null || break; sleep 0.1; done
pkill -9 -a -x LidAgents 2>/dev/null || true
mkdir -p "$(dirname "$APP")"
rm -rf "$APP"
ditto "$src" "$APP"
if [ -d "$OLD_APP" ]; then rm -rf "$OLD_APP"; echo "    Removed the old $OLD_APP"; fi
# Downloads through a browser are quarantined; curl's are not, but clear it either way
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

# 3. The `agents` command
mkdir -p "$BIN_DIR"
if [ -e "$LINK" ] && ! [ -L "$LINK" ]; then
  mv "$LINK" "$LINK.bak"
  echo "    Moved an existing $LINK to $LINK.bak"
fi
ln -sfn "$APP/Contents/Resources/agents" "$LINK"
step "Linked the \`agents\` command: $LINK"

# An upgrade refreshes the OpenCode plugin if `agents integrate` installed it earlier
OPENCODE_PLUGIN="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/lid-agents.js"
if [ -f "$OPENCODE_PLUGIN" ] && [ -f "$APP/Contents/Resources/opencode-lid-agents.js" ]; then
  cp "$APP/Contents/Resources/opencode-lid-agents.js" "$OPENCODE_PLUGIN"
  step "Updated the OpenCode plugin: $OPENCODE_PLUGIN"
fi

# 4. The one permission that needs your password
step "Allowing \`pmset -a disablesleep 0|1\` without a password (nothing else)"
"$LINK" install

# 5. Open at login
mkdir -p "$(dirname "$LAUNCH_AGENT")"
cat > "$LAUNCH_AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
step "Lid Agents will open at login (turn off in its menu)"

# 6. Start it; first launch asks to send notifications
open "$APP"

hotkey="$(defaults read "$BUNDLE_ID" Hotkey 2>/dev/null || echo "ctrl+0")"
echo
bold "Lid Agents $("$LINK" version | awk '{print $2}') is installed."
echo "  • Click the cup in the menu bar, or press $hotkey, to keep agents running with the lid closed."
echo "  • macOS will ask whether \"Lid Agents\" can send notifications: click Allow."
echo "  • In a terminal: agents keep · agents pause · agents (status) · agents uninstall"
if ! [ -f "$OPENCODE_PLUGIN" ]; then
  echo "  • Use Codex or OpenCode? Run \`agents integrate\` so Lid Agents can tell when they're busy."
fi
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo
     echo "  $BIN_DIR is not on your PATH. To use the \`agents\` command, run:"
     echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && exec zsh" ;;
esac
