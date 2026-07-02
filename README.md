# Listener

Listener is an experimental client/server audio playback system. The server
owns playback control and media streaming, while the client workspace contains
the planned UI and native audio engine pieces.

## Repository layout

```text
client/   Client workspace and native client engine experiments.
server/   Zig server implementation.
proto/    Versioned protobuf API definitions.
docs/     Architecture, protocol, and implementation notes.
```

Root-level project files:

```text
.gitignore  Generated output and local machine ignores.
README.md   Project overview and navigation.
```

## Development

Run the server build from the server directory:

```sh
cd server
zig build
```

Run tests:

```sh
cd server
zig build test
```

The client engine has its own Zig package in `client/engine`.
