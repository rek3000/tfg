# TerraFirmaGreg server

Ops tooling for the TerraFirmaGreg-Modern server at `/srv/terrafirmagreg`:
update the pack without losing the world, run it as a service, talk to its
console, and keep LittleSkin external login wired up across updates.

```
/srv/tfg/install.sh     set up service + CLI (idempotent)
/srv/tfg/packs/         server pack zips (drop new versions here, not in git)
/srv/tfg/overrides/     YOUR files, re-applied after every update
/srv/tfg/backups/       pre-update snapshots of your data (10 newest, not in git)
/srv/tfg/update.sh      the updater
/srv/tfg/run.sh         what the service runs (console wiring lives here)
/srv/tfg/gen-ignore.sh  regenerates .gitignore from the pack contents
/srv/tfg/tfg-cmd        send a console command
/srv/tfg/tfg-log        follow the console
/srv/tfg/slp.py         server-list ping, to check reachability
/srv/tfg/server.properties.patch  keys we force in server.properties
/srv/tfg/systemd/       the service unit (symlinked into ~/.config/systemd/user)
/srv/terrafirmagreg/    the live server (NOT in git: ~550 MB of mod jars)
```

## Fresh setup

```
git clone git@github.com:rek3000/tfg.git /srv/tfg
cd /srv/tfg && ./install.sh
# put a server pack zip in packs/, then:
./update.sh
systemctl --user start terrafirmagreg
```

Needs Java 21+ (Minecraft 1.20.1 / Forge 47.4.13) plus `unzip`, `rsync`, `zstd`.

## What is and is not in git

In: the scripts, the service unit, `overrides/`, this README.

Out: the pack zips and `backups/` (size), and the whole live server tree. The
pack-owned part of `.gitignore` is **generated** by `gen-ignore.sh` from the
zip's own top-level listing, and `update.sh` re-runs it, so a future pack that
adds a top-level folder is ignored without anyone editing a list. Edit
`gen-ignore.sh`, never `.gitignore`.

## Connecting (Tailscale)

The box is on the tailnet as **`basement`**, so add this server in Minecraft:

```
basement.tail686c45.ts.net
```

or by IP, `100.104.248.8`. No port needed, it is the default 25565.

Nothing extra to install or configure: the server binds `0.0.0.0`, which
already covers `tailscale0`, and the tailnet has shields-up off. Your laptop
just needs to be logged into the same tailnet (`tailscale up`) and awake.

Check it from anywhere on the tailnet:

```
./slp.py basement.tail686c45.ts.net     # real server-list ping, not just a TCP open
```

Deliberately **not** using `tailscale serve`/`funnel`: those terminate HTTP/TLS,
and the Minecraft protocol is neither.

### It is also exposed on your LAN

`server-ip=0.0.0.0` means the server also answers on `192.168.1.4`, so anyone
on your home network can see it, not only tailnet devices. That is usually
what you want (LAN players skip the tailnet), and `online-mode=true` still
forces a real LittleSkin login, so it is not open to anonymous joins.

To make it tailnet-only, add `server-ip=100.104.248.8` to
`server.properties.patch` and re-run `update.sh`. Trade-off worth knowing before you
do: the server then fails to bind if `tailscale0` is not up yet at boot, and
with `Restart=on-failure` capped at 3 tries it could give up after a reboot
race. Binding `0.0.0.0` has no such startup ordering problem, which is why it
is the default here.

To restrict *who* can join, which is the safer lever, see below. It is already
on.

### Who can join

Whitelist is **on**, with `rek3000` whitelisted and operator (level 4).

```
tfg-cmd whitelist add <name>
tfg-cmd whitelist remove <name>
tfg-cmd whitelist list
```

`whitelist.json` and `ops.json` are your data, so they survive pack updates
untouched. But `whitelist on/off` is runtime state Minecraft writes into
`server.properties`, which is pack-owned and gets replaced, so the switch is
pinned in `server.properties.patch` as `white-list=true`. **If you ever
`whitelist off` and want it to stick, change that file too**, otherwise the
next update turns it back on.

Names are resolved through LittleSkin, not Mojang. Verified: `rek3000` got
UUID `4c4aeaaa-d2f2-4261-b6a3-32ee6974ac4b`, which matches
`littleskin.cn/api/yggdrasil`'s answer exactly. A Mojang account with the same
name would have a different UUID and would not match this whitelist entry.

## Running it

The server is a systemd **user** service, `terrafirmagreg`. Lingering is on for
`base`, so it starts at boot and keeps running after you log out.

```
systemctl --user start terrafirmagreg
systemctl --user stop terrafirmagreg      # types "stop", waits for the save
systemctl --user restart terrafirmagreg
systemctl --user status terrafirmagreg
systemctl --user disable terrafirmagreg   # stop starting at boot
```

Startup takes roughly 90 seconds (206 mods). It is up when the log says
`Done (N.NNNs)!` and port 25565 is listening.

`stop` is graceful: the wrapper types `stop` into the console and waits up to
300s for `All dimensions are saved`, rather than killing the JVM. Never
`kill -9` it.

Crash handling: `Restart=on-failure`, 20s apart, but it gives up after 3 tries
in 10 minutes so a bad mod or config cannot crash-loop forever. After that,
`systemctl --user reset-failed terrafirmagreg` once you have fixed it.

## Talking to the server console

A dedicated-server console is normally stdin of the process, which a service
has no terminal for. `run.sh` points stdin at a FIFO (`console.fifo`) and holds
it open, so you can write to it any time. (This works because the pack's starter
calls `ProcessBuilder.inheritIO()`, so stdin reaches the real Forge server.)

Send a command and see the reply:

```
tfg-cmd list
tfg-cmd say hello everyone
tfg-cmd whitelist add Steve
tfg-cmd "time set day"
tfg-cmd op Steve
tfg-cmd save-all
```

Follow everything live (Ctrl-C only stops watching, the server keeps running):

```
tfg-log
```

Full history, searchable:

```
journalctl --user -u terrafirmagreg --no-pager        # all
journalctl --user -u terrafirmagreg -o cat | grep -i joined
```

Quote anything containing `;`, `&`, or quotes. `tfg-cmd stop` works too, but
prefer `systemctl --user stop` so systemd knows it was intentional and does not
try to restart it.

## Update

1. Download the new server pack zip into `/srv/tfg/packs/`.
2. Run `/srv/tfg/update.sh`            (newest zip in `packs/`)
   or `/srv/tfg/update.sh /srv/tfg/packs/TerraFirmaGreg-Modern-0.13.0-serverpack.zip`
3. `tfg-log` to watch it come back up.

If the service is running, the updater stops it gracefully, updates, and starts
it again. If some *other* server process is running, it refuses rather than
guessing how to shut it down safely.

## The one rule

Anything the zip ships is **pack-owned** and gets wiped and replaced:
`config/ defaultconfigs/ kubejs/ mods/ tacz/ DiscordIntegration-Data/
minecraft_server.jar server.properties server_starter.conf forge-auto-install.txt
start_server.* server-icon.png README.md`

Everything else is **yours** and is never touched:
`world/ logs/ eula.txt ops.json whitelist.json banned-*.json usercache.json
libraries/ versions/ backups/ (ftbbackups2) authlib-injector.jar, extra mods you added`

So: **never hand-edit a pack-owned file and expect it to survive.** Put your
version in `/srv/tfg/overrides/` with the same relative path, e.g.

```
/srv/tfg/overrides/defaultconfigs/tfc-server.toml
/srv/tfg/overrides/mods/some-extra-mod.jar
/srv/tfg/overrides/authlib-injector.jar
```

(For `server.properties`, use `server.properties.patch` instead, see below.)

Overrides are copied in last (via `rsync -a`, so the exec bit is preserved), so
they always win. Already set up this way:

| override | why |
| --- | --- |
| `authlib-injector.jar` | the agent itself |
| `user_jvm_args.txt` | memory + `-javaagent:...=littleskin.cn` |
| `start_server.sh` | the pack version put `-Xmx` after `-jar`, where the JVM ignores it |

`server.properties` is deliberately **not** a whole-file override. The pack
edits it between versions (the MOTD carries the pack version, defaults change),
and a full-file copy silently discards all of that. Instead
`server.properties.patch` lists just the keys we own, and `update.sh` rewrites
those lines in place:

```
online-mode=true            # verify logins with LittleSkin
enforce-secure-profile=false
max-players=10
white-list=true
```

Add a key there to own it, remove it to hand it back to the pack.

## LittleSkin external login (authlib-injector)

Already working, verified on a real boot. The non-obvious part:

`minecraft_server.jar` is **not** the Minecraft server, it is HellBz
Forge-Server-Starter. It installs Forge, then spawns a *second* JVM:

```
java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.13/unix_args.txt nogui
```

That child is the real server. So `-javaagent` goes in **`user_jvm_args.txt`**,
not in `start_server.sh`: an agent on the starter JVM would be thrown away when
the child launches.

`user_jvm_args.txt`:

```
-Xms1024M
-Xmx6024M
-javaagent:authlib-injector.jar=littleskin.cn
```

`littleskin.cn` is shorthand; the agent expands it to
`https://littleskin.cn/api/yggdrasil`.

Side effect worth knowing: once `user_jvm_args.txt` exists, the starter uses it
and ignores `-Xmx`/`-Xms` elsewhere. **Set memory in `user_jvm_args.txt`.**

`server.properties` must keep `online-mode=true`. That switch does not mean
"require a Mojang account", it means "ask the auth server to verify the login".
With it off, the server never calls LittleSkin and anyone can log in under any
name. `enforce-secure-profile` is set to `false`.

Confirm it took effect, in the server output or `authlib-injector.log`:

```
[authlib-injector] [INFO] Authentication server: https://littleskin.cn
[authlib-injector] [INFO] Redirect to: https://littleskin.cn/api/yggdrasil
[authlib-injector] [INFO] Transformed [com.mojang.authlib.yggdrasil.YggdrasilEnvironment] ...
```

Players need a launcher pointed at the same LittleSkin Yggdrasil server (HMCL,
BakaXL, PCL, Prism all support adding an authlib-injector account). Use one auth
source only, never LittleSkin and Mojang at once.

To upgrade the agent, drop the new jar at `/srv/tfg/overrides/authlib-injector.jar`
(keep the filename, or the `-javaagent:` path in `user_jvm_args.txt` has to change
too) and re-run `update.sh`, or just `rsync -a /srv/tfg/overrides/ /srv/terrafirmagreg/`.

Note on `defaultconfigs/`: Minecraft copies those into `world/serverconfig/` the
first time a world is created, and from then on the live values are the ones in
`world/serverconfig/`. Updating the pack will not change an existing world's
settings. To change a running world, edit `world/serverconfig/*.toml` (that is
your data, it survives updates) and mirror it in `overrides/defaultconfigs/` so
a future fresh world starts the same way.

## If an update goes wrong

Your data was snapshotted before extraction:

```
tar -xaf /srv/tfg/backups/data-YYYYmmdd-HHMMSS.tar.zst -C /srv/terrafirmagreg
```

To go back to the old pack, re-run the updater with the old zip. Keep old zips.

## Before a big version jump

Copy the world first, `/srv/tfg/backups/` snapshots exclude nothing but logs but
the rollback path is smoother if you also have the world aside:

```
cp -a /srv/terrafirmagreg/world /srv/tfg/backups/world-pre-0.13
```

Mod updates can change block/item IDs. Read the pack changelog for migration
notes, and expect that world damage from a mod removal is not something a file
copy can undo, which is why the copy comes first.
