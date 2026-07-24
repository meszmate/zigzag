<div align="center">
  <h1>ZigZag</h1>

  <p>A batteries-included TUI framework for Zig.</p>

  <p>
    <a href="https://github.com/meszmate/zigzag/actions"><img src="https://img.shields.io/github/actions/workflow/status/meszmate/zigzag/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status" /></a>
    <a href="https://github.com/meszmate/zigzag/releases"><img src="https://img.shields.io/github/v/release/meszmate/zigzag?style=flat-square" alt="Latest release" /></a>
    <a href="./LICENSE"><img src="https://img.shields.io/github/license/meszmate/zigzag?style=flat-square" alt="MIT license" /></a>
    <img src="https://img.shields.io/badge/Zig-0.16.0-F7A41D?logo=zig&logoColor=white&style=flat-square" alt="Zig 0.16.0" />
  </p>

  <p>
    <a href="#features">Features</a> ·
    <a href="#quick-start">Quick start</a> ·
    <a href="#components">Components</a> ·
    <a href="#examples">Examples</a> ·
    <a href="#documentation">Documentation</a>
  </p>

</div>

![ZigZag component showcase](assets/showcase.gif)

ZigZag combines a predictable Model-Update-View loop with rich styling,
flexible layout, and more than 40 ready-to-use components. It runs on macOS,
Linux, Windows, and WebAssembly with no third-party dependencies.

## Features

| | |
|---|---|
| **Predictable architecture** | Typed messages, commands, sub-programs, screen stacks, timers, and background tasks |
| **Rich styling** | ANSI 16, 256, and TrueColor; adaptive colors; borders; spacing; themes; and text overflow |
| **Flexible layout** | ANSI-aware measurement, placement, Flexbox constraints, split panes, and layered composition |
| **Terminal-native input** | Keyboard and mouse events, bracketed paste, OSC 52 clipboard access, and focus management |
| **Images and graphics** | Kitty, iTerm2, and Sixel images, plus charts, heatmaps, canvases, and Braille drawing |
| **Fast and testable** | Diff-based rendering, ANSI compression, virtual lists, custom I/O, and snapshot helpers |

ZigZag follows the Elm architecture: events become typed messages, `update`
changes the model and returns optional commands, and `view` renders the next
terminal frame.

## Quick start

ZigZag requires Zig 0.16.0 or newer.

```sh
zig fetch --save git+https://github.com/meszmate/zigzag#main
```

Add the module to your executable in `build.zig`:

```zig
const zigzag = b.dependency("zigzag", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zigzag", zigzag.module("zigzag"));
```

Then build your application around a model with `init`, `update`, and `view`
methods. See the small [counter example](examples/counter.zig) for a complete
starting point.

## Components

| Category | Included |
|----------|----------|
| **Input and forms** | Text input, text area, checkbox, radio group, slider, dropdown, form, file picker, stepper |
| **Data and navigation** | Lists, virtual lists, tables, trees, tabs, breadcrumbs, screen stacks |
| **Visualization** | Progress, gauges, sparklines, charts, heatmaps, canvas, Braille canvas |
| **Overlays and feedback** | Modals, confirmations, tooltips, notifications, toasts, context menus, command palette |
| **Content and tooling** | Markdown, code view, diff view, rich log, status bar, help, developer console |

The [component reference](REFERENCE.md#components) includes usage examples
for each major component.

## Examples

Clone the repository and run any example with `zig build run-<name>`.

| Start here | Command |
|------------|---------|
| [Full showcase](examples/showcase.zig) | `zig build run-showcase` |
| [Counter](examples/counter.zig) | `zig build run-counter` |
| [Dashboard](examples/dashboard.zig) | `zig build run-dashboard` |
| [File browser](examples/file_browser.zig) | `zig build run-file_browser` |
| [Charts](examples/charts.zig) | `zig build run-charts` |
| [WebAssembly app](examples/wasm_app.zig) | `zig build run-wasm_app` |

Run `zig build --help` to see every available example.

## Documentation

| Read this | To learn |
|-----------|----------|
| [API and component reference](REFERENCE.md) | Architecture, commands, styling, components, runtime options, terminal features, and layout |
| [Examples](examples/) | Complete applications and focused feature demonstrations |
| [Contributing guide](CONTRIBUTING.md) | Development workflow and contribution guidelines |

## Projects using ZigZag

- [zmenu](https://github.com/menosbits/zmenu) - A simple Zig application launcher for GNU/Linux.

## Star ZigZag ⭐

If ZigZag helps you build a terminal application, consider
[starring the repository](https://github.com/meszmate/zigzag). It helps more Zig
developers find the project.

## Contributing

Pull requests are welcome. Run `zig build` and `zig build test` before opening a
PR, then follow the [contributing guide](CONTRIBUTING.md).

## License

ZigZag is available under the [MIT License](LICENSE).
