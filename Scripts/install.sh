#!/usr/bin/env bash
# Builds MacStatus, installs it into an Applications folder and starts it.
# Once it runs from there it adds itself to Login Items (turn that off from the right-click menu).
#   Scripts/install.sh                      # -> /Applications
#   Scripts/install.sh ~/Applications       # or any other Applications folder
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="${1:-/Applications}"
case "$(basename "$DEST")" in
  Applications) ;;
  *) echo "The destination must be a folder named Applications (launch at login is only set up from there)." >&2; exit 1 ;;
esac

Scripts/build-app.sh release

# Quit the running copy by bundle id ("is running" never launches it), so a reinstall replaces it cleanly.
osascript -e 'if application id "dev.iddhi.MacStatus" is running then tell application id "dev.iddhi.MacStatus" to quit' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$DEST"
rm -rf "$DEST/MacStatus.app"
ditto build/MacStatus.app "$DEST/MacStatus.app"
open "$DEST/MacStatus.app"
echo "Installed $DEST/MacStatus.app and started it."
