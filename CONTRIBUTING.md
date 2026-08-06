# Contributing

Thanks for helping improve Neon Notch. Contributions are welcome.

## Setup and testing

Use Xcode 26.6 or later on macOS 26 or later. Clone the repository, open `NeonNotch.xcodeproj` in Xcode if you prefer the IDE, and use the source-build instructions in [README](README.md#build-from-source) for a local Debug build.

Before submitting a pull request, run the canonical test suite in [README](README.md#testing). Add or update tests when behavior changes. For visual changes, update the relevant tracked design evidence and [design QA guide](docs/design-qa.md) when appropriate.

## Coordination and pull requests

For substantial changes, open an issue before writing the implementation so the scope, approach, and macOS behavior can be discussed. Keep pull requests focused, explain the rationale, link related issues, describe testing, and include screenshots when the user interface changes.

Preserve the local-first privacy model. Do not include credentials, personal paths, private logs, agent transcripts, clipboard contents, or screenshots containing sensitive desktop content.

## Contribution terms

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE). No contributor license agreement or Developer Certificate of Origin is required.
