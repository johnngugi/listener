# Listener

Listener is an experimental client/server audio playback system. The server
owns playback control and media streaming, while the client workspace contains
the planned UI and native audio engine pieces.

## Repository layout

```text
client/   Client workspace and native client engine experiments.
packages/ Shared, independently testable packages such as the LSTN wire protocol.
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

The client engine is a Dart Native Assets package in `client/engine`. Its build
hook compiles the Zig implementation and bundles it with consuming apps.
