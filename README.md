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
    <a href="#how-it-works">How it works</a> ·
    <a href="#quick-start">Quick start</a> ·
    <a href="#components">Components</a> ·
    <a href="#examples">Examples</a> ·
    <a href="REFERENCE.md">Reference</a>
  </p>

  <img src="assets/showcase.gif" alt="ZigZag component showcase" width="800" />
</div>

ZigZag brings typed Model-Update-View applications, rich styling, flexible
layout, and 40+ components to the terminal with no third-party dependencies.

## Features

| Capability | Highlights |
|------------|------------|
| **Architecture** | Typed Model-Update-View, commands, async tasks, sub-programs |
| **Components** | 40+ inputs, tables, lists, charts, forms, and overlays |
| **Styling** | ANSI, 256-color, TrueColor, adaptive themes, borders, and text overflow |
| **Layout** | Placement, Flexbox constraints, split panes, and layered composition |
| **Terminal support** | Keyboard, mouse, clipboard, images, suspend/resume |
| **Performance** | Diff rendering, ANSI compression, and virtual lists |

## How it works

Events update the model, then `view` renders the next terminal frame.

```mermaid
flowchart LR
  E["Input · timer · async"] --> U["update"]
  U --> M["Model"]
  M --> V["view"]
  V --> T["Terminal"]
  U --> C["Command"]
  C --> E
```

## Quick start

Requires Zig 0.16.0 or newer.

```sh
zig fetch --save git+https://github.com/meszmate/zigzag#main
```

```zig
const zigzag = b.dependency("zigzag", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zigzag", zigzag.module("zigzag"));
```

Start with the [counter example](examples/counter.zig).

## Components

| Category | Includes |
|----------|----------|
| **Input and forms** | Text input, text area, checkbox, radio group, slider, dropdown, form, file picker, stepper |
| **Data and navigation** | List, virtual list, table, sortable table, data table, tree, tabs, breadcrumbs, screen stacks |
| **Visualization** | Progress, spinner, gauge, sparkline, chart, bar chart, heatmap, canvas, Braille canvas |
| **Overlays and feedback** | Modal, confirmation, tooltip, notification, toast, context menu, command palette |
| **Content and tooling** | Markdown, code view, diff view, rich log, status bar, help, developer console |

[Browse the component index →](REFERENCE.md#components)

## Examples

| Demo | Run |
|------|-----|
| [Showcase](examples/showcase.zig) | `zig build run-showcase` |
| [Dashboard](examples/dashboard.zig) | `zig build run-dashboard` |
| [File browser](examples/file_browser.zig) | `zig build run-file_browser` |
| [WebAssembly](examples/wasm_app.zig) | `zig build run-wasm_app` |

[See every example →](examples/)

## Documentation

[Reference](REFERENCE.md) · [Examples](examples/) ·
[Contributing](CONTRIBUTING.md)

## Star ZigZag ⭐

If ZigZag helps you build a terminal application, consider
[starring the repository](https://github.com/meszmate/zigzag). Stars help other
Zig developers discover the project, show that the framework is useful, and
motivate continued work on components, terminal support, and documentation.

## License

[MIT](LICENSE)
