#!/bin/bash
# JVM args (memory + the LittleSkin authlib-injector agent) live in
# user_jvm_args.txt, which the Forge child process reads. Do not put -Xmx here:
# the original pack script had it after -jar, where the JVM ignores it.
cd "$(dirname "$0")"
exec java -jar minecraft_server.jar nogui
