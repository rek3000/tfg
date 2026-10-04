#!/usr/bin/env bash
# Update the TerraFirmaGreg server pack in place, keeping world + player data.
#
# Layout:
#   /srv/tfg/packs/*.zip   server pack zips (drop a new one here)
#   /srv/tfg/overrides/    your files, re-applied on top after every update
#   /srv/tfg/backups/      pre-update snapshots of non-pack data
#   /srv/terrafirmagreg/   the live server
#
# Rule: everything the zip ships is pack-owned and gets replaced.
# Everything else (world, logs, ops/whitelist/bans, eula, forge libraries,
# ftbbackups2 output, ...) is yours and is never touched.
# Want a permanent tweak to a pack-owned file? Put it in overrides/.
set -euo pipefail

SERVER=${SERVER:-/srv/terrafirmagreg}
ROOT=$(cd "$(dirname "$0")" && pwd)
PACK=${1:-}

if [[ -z $PACK ]]; then
	PACK=$(ls -1 "$ROOT"/packs/*.zip | sort -V | tail -1)
	echo "No pack given, using newest: $(basename "$PACK")"
fi
[[ -f $PACK ]] || { echo "pack not found: $PACK" >&2; exit 1; }

# Is the server up? Match the Forge child JVM (unix_args.txt) and the
# ServerStarter, not just the path: pgrep -f on $SERVER also matches this
# script, whose own argv contains that path.
UNIT=terrafirmagreg
RESTART=0
if pgrep -f 'unix_args\.txt' >/dev/null || pgrep -f '\-jar minecraft_server\.jar' >/dev/null; then
	# If it is our service, stop it properly (saves the world) and put it back
	# up afterwards. Anything else, refuse: we cannot shut it down safely.
	if systemctl --user is-active --quiet "$UNIT"; then
		echo "Stopping $UNIT (world will be saved) ..."
		systemctl --user stop "$UNIT"
		RESTART=1
	else
		echo "A server is running but it is not the $UNIT service. Stop it first." >&2
		exit 1
	fi
fi

# Top-level names the zip owns.
mapfile -t OWNED < <(unzip -Z1 "$PACK" | sed 's#/.*##' | sort -u)
[[ ${#OWNED[@]} -gt 0 ]] || { echo "empty pack?" >&2; exit 1; }

echo "Pack-owned entries: ${OWNED[*]}"

# Snapshot everything that is NOT pack-owned, so a bad update is reversible.
STAMP=$(date +%Y%m%d-%H%M%S)
SNAP="$ROOT/backups/data-$STAMP.tar.zst"
mkdir -p "$ROOT/backups"
EXCL=()
for n in "${OWNED[@]}"; do EXCL+=(--exclude="./$n"); done
if [[ -d $SERVER ]]; then
	echo "Snapshotting your data -> $SNAP"
	tar -C "$SERVER" "${EXCL[@]}" --exclude=./logs -caf "$SNAP" . || {
		rm -f "$SNAP"; echo "snapshot failed" >&2; exit 1; }
fi

# Replace pack-owned content.
mkdir -p "$SERVER"
for n in "${OWNED[@]}"; do rm -rf -- "$SERVER/$n"; done
echo "Extracting $(basename "$PACK")"
unzip -q -o "$PACK" -d "$SERVER"

# Re-apply your files last so they always win.
if [[ -d $ROOT/overrides ]] && [[ -n $(ls -A "$ROOT/overrides") ]]; then
	echo "Applying overrides"
	rsync -a "$ROOT/overrides/" "$SERVER/"
fi

basename "$PACK" > "$ROOT/.current"
# New pack may ship new top-level entries; keep .gitignore in step.
if [[ -x $ROOT/gen-ignore.sh ]]; then "$ROOT/gen-ignore.sh" >/dev/null; fi
# Keep the 10 newest snapshots.
ls -1t "$ROOT"/backups/data-*.tar.zst 2>/dev/null | tail -n +11 | xargs -r rm -f

echo "Done. Now on $(cat "$ROOT/.current"). Snapshot: $SNAP"

if [[ $RESTART == 1 ]]; then
	echo "Starting $UNIT again ..."
	systemctl --user start "$UNIT"
	echo "Watch it come up with: tfg-log"
fi
