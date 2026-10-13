# Contributing to ZigZag

Thank you for your interest in contributing to ZigZag! This document provides guidelines and information to help you get started.

## Getting Started

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.16.0 or later. Changes must build on both 0.16 and 0.17; run `zig fmt` with 0.16, since 0.17 rewrites `@intFromEnum`/`@enumFromInt` into builtins 0.16 lacks
- Git

### Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/<your-username>/zigzag.git
   cd zigzag
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run the tests:
   ```bash
   zig build test
   ```

4. Try an example to verify everything works:
   ```bash
   zig build run-counter
   ```

## Project Structure

```
zigzag/
├── src/
│   ├── root.zig           # Public API exports
│   ├── core/              # Elm architecture (program, context, command)
│   ├── components/        # Pre-built UI components
│   ├── input/             # Keyboard/mouse input handling
│   ├── layout/            # Layout utilities (join, place, measure)
│   ├── style/             # Styling system (colors, borders, rendering)
│   └── terminal/          # Terminal I/O and platform-specific code
│       └── platform/      # posix.zig, windows.zig
├── tests/                 # Unit tests
├── examples/              # Example applications
├── build.zig              # Build configuration
└── build.zig.zon          # Package manifest
```

## How to Contribute

### Reporting Bugs

- Open an issue on GitHub with a clear description of the bug
- Include steps to reproduce, expected behavior, and actual behavior
- Mention your OS, Zig version, and terminal emulator

### Suggesting Features

- Open an issue describing the feature and its use case
- For significant additions, discuss the approach before starting work

### Submitting Changes

1. Create a branch from `main`:
   ```bash
   git checkout -b feature/your-feature
   # or
   git checkout -b fix/your-bugfix
   ```

2. Make your changes and ensure:
   - All existing tests pass: `zig build test`
   - New functionality includes tests where applicable
   - Examples still build and run correctly: `zig build`
   - Code compiles without warnings

3. Commit your changes with a clear message:
   ```bash
   git commit -m "Short description of the change"
   ```

4. Push your branch and open a pull request against `main`

## Code Guidelines

### Architecture

ZigZag follows the **Elm Architecture** (Model-Update-View). When adding features, keep this pattern in mind:

- **Core logic** goes in `src/core/`
- **Components** go in `src/components/` and must be exported in `src/root.zig`
- **Platform-specific code** goes in `src/terminal/platform/`

### Style

- Follow the existing code style in the project
- Use the Zig standard library naming conventions (camelCase for functions, snake_case for variables)
- Keep functions focused and reasonably sized
- Use descriptive names over comments where possible

### Components

When adding a new component:

1. Create the component file in `src/components/`
2. Export it in `src/root.zig`
3. Add an example in `examples/` if appropriate
4. The component should follow the existing pattern:
   - `init()` for construction
   - `handleKey()` for input handling (if interactive)
   - `view()` for rendering
   - Use the arena allocator from context for per-frame allocations

### Testing

- Tests live in the `tests/` directory
- Add tests for new functionality, especially for styling, input handling, and layout logic
- Run the full test suite before submitting:
  ```bash
  zig build test
  ```

### Cross-Platform

ZigZag supports macOS, Linux, and Windows. When making changes:

- Avoid platform-specific code outside of `src/terminal/platform/`
- Test on your platform and note which platforms you've verified in the PR
- Use `std.posix` / `std.os.windows` through the platform abstraction layer

### Zero Dependencies

ZigZag has no external dependencies and should stay that way. All functionality must be implemented using only the Zig standard library.

## Pull Request Process

1. Ensure CI passes (build + tests run on every PR)
2. Provide a clear description of what the PR does and why
3. Link related issues if applicable
4. Keep PRs focused — one feature or fix per PR

## License

By contributing to ZigZag, you agree that your contributions will be licensed under the [MIT License](LICENSE).
