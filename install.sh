#!/usr/bin/env bash
# Install (or re-install) the service and CLI helpers from this repo.
# Safe to re-run: every step is idempotent.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
UNIT=terrafirmagreg

command -v java >/dev/null || { echo "java not found (need 21+ for MC 1.20.1)" >&2; exit 1; }

mkdir -p ~/.config/systemd/user ~/.local/bin
# Symlink, so editing the repo copy is enough.
ln -sfn "$ROOT/systemd/$UNIT.service" ~/.config/systemd/user/"$UNIT".service
ln -sfn "$ROOT/tfg-cmd" ~/.local/bin/tfg-cmd
ln -sfn "$ROOT/tfg-log" ~/.local/bin/tfg-log
chmod +x "$ROOT"/{run.sh,update.sh,gen-ignore.sh,tfg-cmd,tfg-log}

systemctl --user daemon-reload
systemctl --user enable "$UNIT"

# Survive logout and start at boot.
loginctl enable-linger "$USER" 2>/dev/null ||
	echo "note: could not enable-linger; server may stop when you log out" >&2

echo
echo "Installed. Next:"
echo "  systemctl --user start $UNIT"
echo "  tfg-log          # watch it boot (~90s)"
echo "  tfg-cmd list     # talk to the console"
case :$PATH: in
	*:"$HOME/.local/bin":*) ;;
	*) echo; echo "Add ~/.local/bin to PATH to use tfg-cmd / tfg-log by name." ;;
esac
