# Token Wise

Token Wise is a native macOS SwiftUI app for analyzing Claude Code and Codex
token usage, cost, cache efficiency, and session history.

## Development

```bash
cd apple
swift build
swift test
swift run -c release TokenWiseApp
```

To assemble a distributable app bundle:

```bash
scripts/build-swift-app.sh dev
```

See [apple/README.md](apple/README.md) for the native app architecture and
[docs/RELEASING.md](docs/RELEASING.md) for distribution instructions.
