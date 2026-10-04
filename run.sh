#!/usr/bin/env bash
# Service wrapper: run the server with a console you can type into later,
# and shut it down the way Minecraft wants (the "stop" command, so the world
# is saved) instead of killing the JVM.
#
# The pack's starter does ProcessBuilder.inheritIO(), so whatever arrives on
# this script's stdin reaches the real Forge server console.
set -euo pipefail
cd /srv/terrafirmagreg

FIFO=console.fifo
rm -f "$FIFO"
mkfifo -m 600 "$FIFO"

# Hold the FIFO open for the life of this script. Without a permanent writer,
# each tfg-cmd would close its end and the server would read EOF on its
# console and stop accepting commands.
exec 3<>"$FIFO"

java -jar minecraft_server.jar nogui <"$FIFO" &
SERVER=$!

# systemctl stop -> SIGTERM here -> type "stop" into the console and wait for
# the world to finish saving.
graceful() {
	echo "stop" >&3
	# ServerStarter waits on its child, so this returns once both are done.
	wait "$SERVER" 2>/dev/null || true
}
trap graceful TERM INT

wait "$SERVER" 2>/dev/null || true
exec 3>&-
rm -f "$FIFO"
