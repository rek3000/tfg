#!/usr/bin/env python3
"""Minecraft server-list ping: proves the server answers the real protocol.

Usage: slp.py [host] [port]
Exits non-zero if the server does not return a valid status response.
"""
import json
import socket
import struct
import sys


def varint(n):
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        out += struct.pack("B", b | (0x80 if n else 0))
        if not n:
            return out


def read_varint(sock):
    n = shift = 0
    while True:
        (b,) = struct.unpack("B", sock.recv(1))
        n |= (b & 0x7F) << shift
        if not b & 0x80:
            return n
        shift += 7


def ping(host, port=25565, timeout=10):
    with socket.create_connection((host, port), timeout) as s:
        # Handshake, next state 1 = status.
        h = (
            b"\x00"
            + varint(763)
            + varint(len(host.encode()))
            + host.encode()
            + struct.pack(">H", port)
            + varint(1)
        )
        s.sendall(varint(len(h)) + h)
        s.sendall(varint(1) + b"\x00")  # status request

        read_varint(s)  # packet length
        if read_varint(s) != 0:
            raise RuntimeError("unexpected packet id")
        n = read_varint(s)
        buf = b""
        while len(buf) < n:
            chunk = s.recv(n - len(buf))
            if not chunk:
                raise RuntimeError("connection closed early")
            buf += chunk
        return json.loads(buf.decode("utf-8"))


if __name__ == "__main__":
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 25565
    try:
        d = ping(host, port)
    except Exception as e:
        print(f"{host}:{port} ping FAILED: {e}")
        sys.exit(1)
    desc = d.get("description")
    if isinstance(desc, dict):
        desc = desc.get("text") or "".join(
            x.get("text", "") for x in desc.get("extra", [])
        )
    p = d.get("players", {})
    print(f"{host}:{port} OK")
    print(f"  motd:    {desc}")
    print(f"  version: {d.get('version', {}).get('name')}")
    print(f"  players: {p.get('online')}/{p.get('max')}")
