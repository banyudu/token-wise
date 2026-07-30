# Token Wise

Token Wise is a native macOS SwiftUI app for analyzing Claude Code and Codex
token usage, cost, cache efficiency, and session history.

Token Wise is open source under the [MIT License](LICENSE). Download the latest
signed macOS build from [GitHub Releases](https://github.com/banyudu/token-wise/releases/latest),
or build the app from source below. The app is designed for macOS 14 or later.

The app reads local Claude Code and Codex history from your Mac. It does not
upload usage data, require an account, or include telemetry.

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

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/banyudu/token-wise).
Please run `cd apple && swift build && swift test` before opening a pull request.
