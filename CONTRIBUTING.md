# Contributing to Eigenframe

Thank you for taking the time to contribute. Eigenframe is a small open source project and all contributions are welcome.

## Getting Started

1. Fork the repository and clone your fork
2. Make sure you have Xcode 15 or later and macOS 14 or later
3. Open the project: `open Package.swift`
4. Build and run with Cmd + R

## Reporting Bugs

Open an issue and include:

- macOS version
- Steps to reproduce the problem
- What you expected to happen
- What actually happened
- Any relevant output from Console.app filtered by subsystem `com.eigenframe.app`

## Submitting Changes

1. Create a branch from `main` with a descriptive name: `fix/window-level-after-sleep`
2. Make your changes
3. Test on at least one Apple Silicon Mac running macOS 14 or later
4. Open a pull request with a clear description of the change and why it is needed

## Code Style

- Follow Swift API Design Guidelines
- Use `@MainActor` on any type that touches UIKit or AppKit
- Log meaningful events using the subsystem loggers in `Log.swift`
- Avoid force unwraps; handle errors explicitly
- Add a comment explaining any non-obvious behaviour, particularly around private macOS APIs

## Private API Usage

Eigenframe uses `CGSGetActiveSpace` and `CGSCopyManagedDisplaySpaces` from the private CoreGraphics Services layer. These APIs have been stable since macOS Mojave (10.14). Any change that adds further private API usage must include a comment explaining why no public alternative exists and what the fallback behaviour is if the API changes.

## License

By contributing you agree that your contributions will be licensed under the MIT License.
