# ZigZag reference

Detailed API and component documentation for ZigZag.

[Back to the project overview](README.md)

- [Core concepts](#core-concepts)
- [Components](#components)
- [Program options](#program-options)
- [Terminal features](#terminal-features)
- [Layout utilities](#layout-utilities)

## Core concepts

### The Elm architecture

ZigZag uses the Elm Architecture (Model-Update-View):

1. **Model** - Your application state
2. **Msg** - Messages that describe state changes
3. **init** - Initialize your model
4. **update** - Handle messages and update state
5. **view** - Render your model to a string

### Commands

Commands let you perform side effects:

```zig
return .quit;                          // Quit the application
return .none;                          // Do nothing
return .{ .tick = ns };                // Request a tick after `ns` nanoseconds
return Cmd(Msg).everyMs(16);           // Repeating tick every 16ms (~60fps)
return Cmd(Msg).tickMs(1000);          // One-shot tick after 1 second
return .suspend_process;               // Suspend (like Ctrl+Z)
return .enable_mouse;                  // Enable mouse tracking at runtime
return .disable_mouse;                 // Disable mouse tracking
return .show_cursor;                   // Show terminal cursor
return .hide_cursor;                   // Hide terminal cursor
return .{ .set_title = "My App" };     // Set terminal window title
return .{ .println = "Log message" };  // Print above the program output
return .repaint;                       // Repaint the whole frame next render
return .{ .image_file = .{             // Draw image via Kitty/iTerm2/Sixel when available
    .path = "assets/cat.png",
    .width_cells = 40,
    .height_cells = 20,
    .placement = .center,              // .cursor, .top_left, .top_center, .center
    .row_offset = -6,                  // Negative = higher, positive = lower
    .col_offset = 0,                   // Negative = left, positive = right
    // .row = 2, .col = 10,            // Optional absolute position override
    .move_cursor = false,              // Helpful for iTerm2 placement
    .protocol = .auto,                 // .auto, .kitty, .iterm2, .sixel
    .z_index = -1,                     // Kitty: render behind text
    .unicode_placeholder = false,       // Kitty: participate in text reflow
} };
return .{ .image_data = .{            // Draw in-memory image data
    .data = png_bytes,                 // Raw RGB, RGBA, or PNG bytes
    .format = .png,                    // .rgb, .rgba, .png
    .pixel_width = 100,                // Required for RGB/RGBA
    .pixel_height = 100,
    .width_cells = 20,
    .height_cells = 10,
    .placement = .center,
} };
return .{ .cache_image = .{           // Upload to Kitty cache (transmit once)
    .source = .{ .file = "assets/logo.png" },
    .image_id = 1,
} };
return .{ .place_cached_image = .{    // Display cached image (no re-upload)
    .image_id = 1,
    .placement = .center,
    .width_cells = 20,
    .height_cells = 10,
} };
return .{ .delete_image = .{ .by_id = 1 } };  // Free cached image
return .{ .delete_image = .all };              // Free all cached images
```

#### Batch lifetimes

`batch` and `sequence` hold a **slice**, which the runtime reads after `update`
has returned. A `&.{ ... }` literal only lives in static memory when every
element is comptime-known — one runtime value in there and the array becomes a
stack temporary that is gone by the time the runtime walks it:

```zig
// Wrong: `row` is a runtime value, so this slice dangles on return.
return .{ .batch = &.{
    .{ .cache_image = .{ .source = .{ .file = path }, .image_id = 1 } },
    .{ .place_cached_image = .{ .image_id = 1, .row = row } },
} };
```

Either copy it into the frame allocator:

```zig
return try zz.Cmd(Msg).batchAlloc(ctx.allocator, &.{
    .{ .cache_image = .{ .source = .{ .file = path }, .image_id = 1 } },
    .{ .place_cached_image = .{ .image_id = 1, .row = row } },
});
```

or keep the storage on the model, which outlives any single `update`:

```zig
pending_batch: [2]zz.Cmd(Msg) = undefined,
// ...
self.pending_batch = .{ cache_cmd, place_cmd };
return .{ .batch = &self.pending_batch };
```

A batch of nothing but comptime-known commands is fine as a literal.

### Styling

Build styles by chaining properties:

```zig
const style = (zz.Style{})
    .bold(true)
    .italic(true)
    .fg(.cyan)
    .bg(.black)
    .paddingAll(1)
    .marginAll(2)
    .marginBackground(.gray(3))
    .borderAll(.rounded)
    .borderForeground(.magenta)
    .borderTopForeground(.cyan)    // Per-side border colors
    .borderBottomForeground(.green)
    .tabWidth(4)
    .width(40)
    .alignH(.center);

const output = try style.render(allocator, "Hello, World!");
// render() does not append an implicit trailing '\n'

// Text transforms
const upper_style = (zz.Style{}).transform(.uppercase);
const shouting = try upper_style.render(allocator, "hello"); // "HELLO"

// Inline mode is useful when embedding block-styled output in a single line
const inline = (zz.Style{}).fg(.cyan).inline_style(true);

// Whitespace formatting controls
const ws_style = (zz.Style{})
    .underline(true)
    .setUnderlineSpaces(true)      // Underline extends through spaces
    .setColorWhitespace(false);     // Don't apply bg color to whitespace

// Unset individual properties
const derived = style.unsetBold().unsetPadding().unsetBorder();

// Style inheritance (unset values inherit from parent)
const child = (zz.Style{}).fg(.red).inherit(style);

// Style ranges - apply different styles to byte ranges
const ranges = &[_]zz.StyleRange{
    .{ .start = 0, .end = 5, .s = (zz.Style{}).bold(true) },
};
const ranged = try zz.renderWithRanges(allocator, "Hello World", ranges);

// Highlight specific positions (for fuzzy match results)
const highlighted = try zz.renderWithHighlights(allocator, "hello", &.{0, 2}, highlight_style, base_style);
```

### Colors

```zig
// Basic ANSI colors
zz.Color.red
zz.Color.cyan
zz.Color.brightGreen

// 256-color palette
zz.Color.color256(123)
zz.Color.gray(15)  // 0-23 grayscale

// True color (24-bit)
zz.Color.fromRgb(255, 128, 64)
zz.Color.hex("#FF8040")

// Adaptive colors (change based on terminal capabilities)
const adaptive = zz.AdaptiveColor{
    .true_color = .hex("#FF8040"),
    .color_256 = .color256(208),
    .ansi = .red,
};
const resolved = adaptive.resolve(ctx.true_color, ctx.color_256);

// Color profile detection (automatic via context)
// ctx.color_profile: .ascii, .ansi, .ansi256, .true_color
// ctx.is_dark_background: bool

// Color interpolation (for gradients)
const mid = zz.interpolateColor(.red, .green, 0.5);
```

### Borders

```zig
zz.Border.normal           // ┌─┐
zz.Border.rounded          // ╭─╮
zz.Border.double           // ╔═╗
zz.Border.thick            // ┏━┓
zz.Border.ascii            // +-+
zz.Border.block            // ███
zz.Border.dashed           // ┌╌┐
zz.Border.dotted           // ┌┈┐
zz.Border.inner_half_block // ▗▄▖
zz.Border.outer_half_block // ▛▀▜
zz.Border.markdown         // |-|
```

## Components

Use this index to jump directly to a component or related system.

| Category | Reference |
|----------|-----------|
| **Input and navigation** | [`TextInput`](#textinput) · [`TextArea`](#textarea) · [`List`](#list) · [`Viewport`](#viewport) · [`Table`](#table) · [`Tree`](#tree) · [`StyledList`](#styledlist) · [`TabGroup`](#tabgroup) · [`Calendar`](#calendar) · [`VirtualList`](#virtuallist) · [`SortableTable`](#sortabletable) |
| **Visualization** | [`Progress`](#progress) · [`Spinner`](#spinner) · [`Sparkline`](#sparkline) · [`Chart`](#chart) · [`BarChart`](#barchart) · [`Canvas`](#canvas) · [`Gauge`](#gauge) · [`Heatmap`](#heatmap) |
| **Overlays and feedback** | [`Notification` / `Toast`](#notificationtoast) · [`Confirm`](#confirm) · [`Modal`](#modal) · [`Tooltip`](#tooltip) |
| **Content and developer tools** | [`CodeView`](#codeview) · [`DiffView`](#diffview) |
| **Architecture and layout** | [`SubProgram`](#subprogram) · [`AsyncRunner`](#asyncrunner) · [Flexbox](#flexbox-layout) · [Layer compositing](#layer-compositing) · [Text overflow](#text-overflow) |
| **Interaction** | [Keybinding management](#keybinding-management) · [Focus management](#focus-management) |
| **Additional components** | [`Help`, `Paginator`, `Timer`, and `FilePicker`](#more-components) |

### TextInput

Single-line text input with cursor, validation, autocomplete, and word-level movement:

```zig
var input = zz.TextInput.init(allocator);
input.setPlaceholder("Enter name...");
input.setPrompt("> ");
input.setSuggestions(&.{ "hello", "help", "world" }); // Tab to accept
// Supports: Alt+Left/Right for word movement, Ctrl+W delete word
input.handleKey(key_event);
const view = try input.view(allocator);
```

### TextArea

Multi-line text editor:

```zig
var editor = zz.components.TextArea.init(allocator);
editor.setSize(80, 24);
editor.line_numbers = true;
editor.handleKey(key_event);
```

### List

Selectable list with fuzzy filtering and status bar:

```zig
var list = zz.List(MyItem).init(allocator);
list.multi_select = true;
list.show_item_count = true;  // Shows "3/10 items"
try list.addItem(.init(item, "Item 1"));
// Fuzzy filtering: press / to filter, matches score by consecutive chars
list.handleKey(key_event);
```

### Viewport

Scrollable content area with wrapping, horizontal scrolling, customizable scrollbar chars/styles, and built-in navigation keys (`j/k/h/l`, arrows, `PgUp/PgDn`, `g/G`, `d/u`):

```zig
var viewport = zz.Viewport.init(allocator, 80, 24);
try viewport.setContent(long_text);
viewport.setWrap(true);
viewport.setScrollbarChars("·", "█");
viewport.setScrollbarStyle(
    (zz.Style{}).fg(.gray(8)).inline_style(true),
    (zz.Style{}).fg(.cyan).inline_style(true),
);
viewport.handleKey(key_event);  // Supports j/k, Page Up/Down, etc.
```

### Progress

Progress bar with optional color gradients:

```zig
var progress = zz.Progress.init();
progress.setWidth(40);
progress.setGradient(.hex("#FF6B6B"), .hex("#4ECDC4"));
progress.setPercent(75);
const bar = try progress.view(allocator);
```

### Spinner

Animated loading indicator:

```zig
var spinner = zz.Spinner.init();
spinner.update(elapsed_ns);
const view = try spinner.viewWithTitle(allocator, "Loading...");
```

### Table

Interactive tabular data display with row selection and navigation:

```zig
var table = zz.Table(3).init(allocator);
table.setHeaders(.{ "Name", "Age", "City" });
try table.addRow(.{ "Alice", "30", "NYC" });
try table.addRow(.{ "Bob", "25", "LA" });
table.focus();  // Enable interactive mode
table.show_row_borders = true;  // Horizontal separators between rows
// Supports: j/k, up/down, pgup/pgdown, g/G for navigation
table.handleKey(key_event);
const selected = table.selectedRow();  // Get highlighted row index
```

### Tree

Hierarchical tree view with customizable enumerators:

```zig
var tree = zz.Tree(void).init(allocator);
const root = try tree.addRoot({}, "project/");
const src = try tree.addChild(root, {}, "src/");
_ = try tree.addChild(src, {}, "main.zig");
const view = try tree.view(allocator);
// Output:
// project/
// └── src/
//     └── main.zig
```

### StyledList

Rendering list with enumerators (bullet, arabic, roman, alphabet):

```zig
var list = zz.StyledList.init(allocator);
list.setEnumerator(.roman);
try list.addItem("First item");
try list.addItem("Second item");
try list.addItemNested("Sub-item", 1);
// Output:
// I. First item
// II. Second item
//   I. Sub-item
```

### Sparkline

Mini chart using Unicode block elements with configurable bucketing, ranges, and gradients:

```zig
var spark = zz.Sparkline.init(allocator);
spark.setWidth(20);
spark.setSummary(.average);
spark.setGradient(.hex("#F97316"), .hex("#22C55E"));
try spark.push(10.0);
try spark.push(25.0);
try spark.push(15.0);
const chart = try spark.view(allocator);
```

### Chart

Cartesian chart with multiple datasets, axes, grid lines, legends, selectable markers, and interpolation modes (`linear`, stepped, `catmull_rom`, `monotone_cubic`):

Charts are passive views over your data. They do not animate on their own; they only change when your model updates the dataset. `zig build run-charts` and the `Charts` tab in `zig build run-showcase` demonstrate both static snapshot charts and slower sampled/live updates. The standalone `run-charts` demo now renders as a compact chart dashboard that fits like the other examples instead of behaving like a scrollable document.

![Charts Example](assets/charts.jpg)

```zig
var chart = zz.Chart.init(allocator);
chart.setSize(48, 16);
chart.setMarker(.braille);
chart.x_axis = .{ .title = "Time", .tick_count = 5, .show_grid = true };
chart.y_axis = .{ .title = "CPU", .tick_count = 5, .show_grid = true };

var dataset = try zz.ChartDataset.init(allocator, "load");
dataset.setStyle((zz.Style{}).fg(.cyan).bold(true));
dataset.setShowPoints(true);
dataset.setInterpolation(.monotone_cubic);
dataset.setInterpolationSteps(10);
try dataset.setPoints(&.{
    .{ .x = 0, .y = 20 },
    .{ .x = 1, .y = 45 },
    .{ .x = 2, .y = 30 },
});
try chart.addDataset(dataset);

const view = try chart.view(allocator);
```

### BarChart

Vertical or horizontal bar chart with labels, values, and positive/negative baselines:

```zig
var bars = zz.BarChart.init(allocator);
bars.setOrientation(.horizontal);
bars.show_values = true;
try bars.addBar(try .init(allocator, "api", 31));
try bars.addBar(try .init(allocator, "db", -12));
const view = try bars.view(allocator);
```

### Canvas

Low-level plotting canvas for custom graphs, scatter plots, and braille-dot drawing:

```zig
var canvas = zz.Canvas.init(allocator);
defer canvas.deinit();

canvas.setSize(24, 10);
canvas.setMarker(.braille);
canvas.setRanges(.{ .min = -1, .max = 1 }, .{ .min = -1, .max = 1 });
try canvas.drawLineStyled(-1, -1, 1, 1, (zz.Style{}).fg(.yellow), null);
try canvas.drawPointStyled(0.25, 0.7, (zz.Style{}).fg(.cyan), null);
const view = try canvas.view(allocator);
```

### Notification/Toast

Auto-dismissing timed messages with severity levels:

```zig
var notifs = zz.Notification.init(allocator);
try notifs.push("Build complete!", .success, 3000, current_ns);
notifs.update(current_ns);  // Removes expired notifications
const view = try notifs.view(allocator);
```

### Confirm

Simple yes/no confirmation dialog:

```zig
var confirm = zz.Confirm.init("Are you sure?");
confirm.show();
confirm.handleKey(key_event);  // Left/Right, Enter, y/n
if (confirm.result()) |yes| {
    if (yes) { /* confirmed */ }
}
```

### Modal

Dialog overlay with buttons, backdrop, and focus support:

```zig
var modal = zz.Modal.info("Notice", "Operation completed successfully.");
modal.show();

// In update:
modal.handleKey(key_event);
if (modal.getResult()) |res| {
    switch (res) {
        .button_pressed => |idx| { /* button at idx was pressed */ },
        .dismissed => { /* user pressed Escape */ },
    }
}

// In view:
if (modal.isVisible()) {
    return modal.viewWithBackdrop(allocator, ctx.width, ctx.height);
}
```

Presets: `Modal.info()`, `Modal.confirm()`, `Modal.warning()`, `Modal.err()`, or `Modal.init()` for full custom.

### Tooltip

Contextual hint positioned near a target element with cell-based overlay compositing:

```zig
var tip = zz.Tooltip.init("Save the current document");
tip.target_x = 10;
tip.target_y = 5;
tip.placement = .bottom; // .top, .bottom, .left, .right
tip.show();

// In view — overlays onto existing content:
if (tip.isVisible()) {
    return tip.overlay(allocator, base_view, ctx.width, ctx.height);
}
```

Presets: `Tooltip.init(text)`, `Tooltip.titled(title, text)`, `Tooltip.help(text)`, `Tooltip.shortcut(label, key)`. Supports `border_bg`, `arrow_bg`, `content_bg`, and `inherit_bg` for full background control.

### TabGroup

Multi-screen tab navigation with fully customizable keymaps, styles, and optional per-tab route callbacks:

```zig
var tabs = zz.TabGroup.init(allocator);
defer tabs.deinit();

tabs.show_numbers = true;
tabs.max_width = 60;      // overflow-aware tab strip
tabs.overflow_mode = .scroll; // .none, .clip, .scroll
tabs.activate_on_focus = true; // set false for manual activation

_ = try tabs.addTab(.{ .id = "home", .title = "Home" });
_ = try tabs.addTab(.{ .id = "logs", .title = "Logs", .enabled = false });
_ = try tabs.addTab(.{ .id = "settings", .title = "Settings" });

// In update:
const result = tabs.handleKey(key_event); // Left/Right, Home/End, 1..9 by default
_ = result.change; // optional active-tab change info

// Optional: route unconsumed keys to active tab callback
const routed = tabs.handleKeyAndRoute(key_event).routed;
_ = routed;

// In view:
const strip = try tabs.view(allocator);
const with_content = try tabs.viewWithContent(allocator, "No active tab");
```

Per-tab route callback hooks: `render_fn`, `key_fn`, `on_enter_fn`, `on_leave_fn`.

### Gauge

Visual meter with bar, level meter, and block display styles:

```zig
var gauge = zz.Gauge{};
gauge.value = 73.5;
gauge.width = 40;
gauge.display_style = .bar;     // .bar, .level_meter, .blocks
gauge.show_percent = true;
gauge.label = "CPU";
gauge.full_char = "\xe2\x96\x88";   // Customizable fill character
gauge.empty_char = "\xe2\x96\x91";  // Customizable empty character
gauge.thresholds = &.{
    .{ .value = 80, .color = .yellow },
    .{ .value = 90, .color = .red },
};
const output = gauge.view(allocator);
```

### Heatmap

2D data visualization with configurable color scales:

```zig
var heatmap = zz.Heatmap.init(allocator);
heatmap.setData(7, 24, data);
heatmap.row_labels = &.{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
heatmap.color_scale = .green_scale; // .green_scale, .cool_to_hot, .grayscale, .blue_red
heatmap.cell_width = 3;
heatmap.show_legend = true;
heatmap.show_values = true;
const output = heatmap.view(allocator);
```

### Calendar

Month view date picker with keyboard navigation:

```zig
var cal = zz.Calendar{};
cal.year = 2026;
cal.month = 3;
cal.today_day = 30;
cal.today_month = 3;
cal.today_year = 2026;
cal.cell_width = 4;                // Column width for alignment
cal.week_start_monday = true;
cal.day_headers_mon = .{ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }; // Customizable
cal.month_names = .{ "Jan", "Feb", ... };  // Customizable
cal.prev_symbol = "\xe2\x97\x80"; // Customizable nav symbols
cal.addMarkedDate(25, .red);
cal.update(key_event);             // Arrows, Enter, PgUp/PgDn, Shift+L/R
const output = cal.view(allocator);
```

### VirtualList

Efficient lazy-rendered list for large datasets (100K+ items):

```zig
var vlist = zz.components.virtual_list.VirtualList(usize){};
vlist.items = &huge_dataset;
vlist.viewport_height = 20;
vlist.render_fn = &myRenderFn;
vlist.wrap_around = true;         // Cursor wraps at ends
vlist.empty_text = "No items";    // Custom empty state
vlist.cursor_symbol = "> ";       // Customizable
vlist.show_scrollbar = true;
vlist.update(key_event);
const output = vlist.view(allocator);
```

### SortableTable

Table with column sorting and text filtering:

```zig
var table = zz.components.sortable_table.SortableTable(4).init(allocator);
table.setHeaders(.{ "Name", "Role", "City", "Score" });
try table.addRow(.{ "Alice", "Engineer", "NYC", "95" });
// Press 1-4 to sort by column, / to filter
table.update(key_event);
const output = table.view(allocator);
```

### CodeView

Syntax-highlighted code display:

```zig
var cv = zz.components.code_view.CodeView{};
cv.source = source_code;
cv.language = .zig;               // .zig, .python, .javascript, .go, .rust, .plain
cv.show_line_numbers = true;
cv.highlight_line = 5;            // Highlight a specific line
cv.line_separator = "\xe2\x94\x82"; // Customizable separator
// All token styles are customizable: keyword_style, string_style,
// comment_style, number_style, type_style, builtin_style
const output = cv.view(allocator);
```

### DiffView

Unified and side-by-side diff display:

```zig
var dv = zz.components.diff_view.DiffView{};
dv.old_text = old_source;
dv.new_text = new_source;
dv.old_label = "before";
dv.new_label = "after";
dv.mode = .unified;               // .unified, .side_by_side
dv.side_width = 40;               // Width per side in side-by-side mode
dv.add_prefix = "+";              // Customizable prefixes
dv.remove_prefix = "-";
const output = dv.view(allocator);
```

### SubProgram

Embed independent child models inside a parent:

```zig
const Counter = struct { ... }; // Has Msg, init, update, view

const Model = struct {
    child: zz.SubProgram(Counter, Msg),
    // ...
    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.child = .{};
        _ = self.child.init(ctx);
    }
    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        return self.child.update(.{ .key = k }, ctx);
    }
    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        return self.child.view(ctx);
    }
};
```

### AsyncRunner

Spawn background tasks that deliver messages on completion:

```zig
var runner = zz.AsyncRunner(Msg).init(allocator);
_ = runner.spawn(&myBackgroundTask);    // Returns task ID
// Each frame:
const results = runner.poll();          // Collect completed messages
for (results) |msg| { /* process */ }
```

### Flexbox layout

Constraint-based layout engine:

```zig
const areas = try zz.flex.layout(allocator, width, height, &.{
    .{ .constraint = .{ .fixed = 3 } },       // Header: 3 rows
    .{ .constraint = .fill },                   // Body: remaining space
    .{ .constraint = .{ .percentage = 10 } },  // Footer: 10%
}, .{ .direction = .column, .gap = 1 });
// areas[0].x, areas[0].y, areas[0].width, areas[0].height
```

Constraints: `fixed(n)`, `percentage(pct)`, `min(n)`, `max(n)`, `ratio(num, den)`, `fill`. Options: direction, gap, alignment, justify, wrap.

### Layer compositing

Z-ordered overlay system for popups and modals:

```zig
var stack = zz.layout.layer.LayerStack.init(allocator);
stack.setSize(width, height);
stack.push(.{ .content = background, .z = 0 }) catch {};
stack.push(.{ .content = popup, .x = 10, .y = 5, .z = 10 }) catch {};
const output = stack.render(allocator);
```

### Text overflow

Integrated into the Style system:

```zig
var s = zz.Style{};
s = s.width(40);
s = s.overflow(.ellipsis);  // .visible, .hidden, .ellipsis, .word_wrap, .char_wrap
const output = try s.render(allocator, long_text);
```

### More components

- **Help** - Display key bindings with responsive truncation
- **Paginator** - Pagination controls
- **Timer** - Countdown/stopwatch with warning thresholds
- **FilePicker** - File system navigation

### Keybinding management

Structured key binding definitions with matching and Help integration:

```zig
var keymap = zz.KeyMap.init(allocator);
defer keymap.deinit();

try keymap.addChar('q', "Quit");
try keymap.addCtrl('s', "Save");
try keymap.add(.{
    .key_event = zz.KeyEvent{ .key = .up },
    .description = "Move up",
    .short_desc = "up",
});

// Check if a key event matches any binding
if (keymap.match(key_event)) |binding| {
    // Handle the matched binding
    _ = binding.description;
}

// Generate help text from keybindings
var help = try zz.components.Help.fromKeyMap(allocator, &keymap);
defer help.deinit();
const help_view = try help.view(allocator);
```

### Focus management

Manage Tab/Shift+Tab cycling between interactive components with `FocusGroup`:

```zig
const Model = struct {
    name: zz.TextInput,
    email: zz.TextInput,
    focus: zz.FocusGroup(2),
    focus_style: zz.FocusStyle,

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.name = zz.TextInput.init(ctx.persistent_allocator);
        self.email = zz.TextInput.init(ctx.persistent_allocator);

        self.focus = .{};
        self.focus.add(&self.name);   // index 0
        self.focus.add(&self.email);  // index 1
        self.focus.initFocus();       // focus first, blur rest

        self.focus_style = .{};       // cyan/gray borders by default
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                // Tab/Shift+Tab cycles focus (returns true if consumed)
                if (self.focus.handleKey(k)) return .none;
                // Forward to all — unfocused components auto-ignore
                self.name.handleKey(k);
                self.email.handleKey(k);
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        // Apply focus ring (border color changes based on focus)
        var style = zz.Style{};
        style = style.paddingAll(1);
        const name_style = self.focus_style.apply(style, self.focus.isFocused(0));
        const email_style = self.focus_style.apply(style, self.focus.isFocused(1));
        // ... render with styled boxes ...
    }
};
```

Any component with `focused: bool`, `focus()`, and `blur()` methods works with `FocusGroup`.
Built-in focusable components: TextInput, TextArea, Table, List, Confirm, FilePicker.

#### Custom navigation keys

By default Tab moves forward and Shift+Tab moves backward. Add or replace bindings freely:

```zig
// Add arrow keys and vim j/k alongside the default Tab
fg.addNextKey(.{ .key = .down });              // Down arrow
fg.addNextKey(.{ .key = .{ .char = 'j' } });  // vim j
fg.addPrevKey(.{ .key = .up });                // Up arrow
fg.addPrevKey(.{ .key = .{ .char = 'k' } });  // vim k

// Or replace defaults entirely
fg.setNextKey(.{ .key = .down });  // Down only, Tab no longer works
fg.setPrevKey(.{ .key = .up });    // Up only

// Clear all bindings (manual-only via focusNext/focusPrev)
fg.clearNextKeys();
fg.clearPrevKeys();

// Modifier keys work too
fg.addNextKey(.{ .key = .{ .char = 'n' }, .modifiers = .{ .ctrl = true } }); // Ctrl+N
```

Up to 4 bindings per direction. Modifier matching is exact (Ctrl+Tab won't match a plain Tab binding).

#### Additional API

```zig
fg.focusAt(2);           // Focus specific index
fg.focusNext();          // Manual next
fg.focusPrev();          // Manual prev
fg.blurAll();            // Remove focus from all
fg.focused();            // Get current index
fg.isFocused(1);         // Check if index is focused
fg.len();                // Number of registered items

// Disable wrapping (stop at ends instead of cycling)
var fg: zz.FocusGroup(3) = .{ .wrap = false };

// Custom focus ring colors
const fs = zz.FocusStyle{
    .focused_border_fg = .green,
    .blurred_border_fg = .gray(8),
    .border_chars = .double,
};
```

## Program options

Configure the program with custom options:

```zig
var program = zz.Program(Model).initWithOptions(init.gpa, init.io, init.environ_map, .{
    .fps = 60,                  // Target frame rate
    .alt_screen = true,         // Use alternate screen buffer
    .mouse = false,             // Enable mouse tracking
    .cursor = false,            // Show cursor
    .bracketed_paste = true,    // Enable bracketed paste mode
    .kitty_keyboard = false,    // Enable Kitty keyboard protocol
    .osc52 = .{                 // OSC 52 clipboard defaults
        .enabled = true,
        .query_enabled = true,  // Allow OSC 52 clipboard reads (query)
        .target = .clipboard,   // .primary, .secondary, .select, .cut_buffer, .raw
        .terminator = .bel,     // .bel or .st
        .passthrough = .auto,   // .auto, .none, .tmux, .dcs
        .max_bytes = null,      // Optional write payload limit
        .query_timeout_ms = 180,
        .max_read_bytes = null, // Optional decoded read limit
        .strict_query_target = false,
    },
    .unicode_width_strategy = null, // null=auto, .legacy_wcwidth, .unicode
    .suspend_enabled = true,    // Enable Ctrl+Z suspend/resume
    .escape_timeout_ms = 50,    // How long a lone ESC waits for a sequence
    .render_mode = .diff,       // .diff rewrites changed lines, .full rewrites everything
    .title = "My App",         // Window title
    .log_file = "debug.log",   // Debug log file path
    .input = custom_stdin,      // Custom input (for testing/piping)
    .output = custom_stdout,    // Custom output (for testing/piping)
});
```

`escape_timeout_ms` exists because a bare `ESC` is byte-for-byte the beginning of
every arrow key, function key and mouse report. The runtime holds a lone `ESC`
for this long, and delivers it as the Escape key only if nothing follows.
Lower it for a snappier Escape; raise it when sequences arrive in pieces over a
slow link.

Unicode width strategy can also be overridden per-process with `ZZ_UNICODE_WIDTH=auto|legacy|unicode`.
By default (`null`/`auto`), ZigZag:
- probes DEC mode `2027` and enables it when available,
- probes kitty text-sizing support,
- applies terminal/multiplexer heuristics (e.g. tmux/screen/zellij favor legacy width).

### Rendering

`view()` returns the whole frame as a string; the runtime works out what to
send to the terminal.

With the default `render_mode = .diff`, a frame is compared line by line
against the one before it and only the rows that changed are rewritten. An
animated spinner next to a screenful of streaming text costs a few dozen bytes
per frame instead of a few thousand, which is the difference between a busy
event loop and an idle one at 60fps.

Diffing needs frame row `n` to really be terminal row `n`, so it steps aside
and repaints in full whenever that does not hold:

- a line wider than the terminal (it would wrap and shift everything below it)
- a frame taller than the terminal (it would scroll)
- a line that leaves a colour or attribute switched on, since the lines under
  it inherit that styling and cannot be redrawn on their own
- the frame after any of the above

The runtime also repaints in full after a resize, a suspend/resume, an inline
image, `println`, and alt-screen switches. If something *outside* the framework
writes to the terminal — a library printing to stderr, a shelled-out command —
tell the renderer its picture is stale:

```zig
return .repaint;        // from update()
program.invalidate();   // from a custom event loop
```

Set `render_mode = .full` to always rewrite every line, which is
self-correcting at the cost of a screenful of output per frame.

The renderer is usable on its own — `zz.FrameRenderer` over any
`std.Io.Writer` — if you drive the terminal yourself.

### Allocator lifetimes

`ctx.allocator` is a frame allocator that is reset before each `tick()`.
Use it for temporary values (render strings, per-frame buffers).

For model state that must live across frames, allocate with `ctx.persistent_allocator`.

### Custom event loop

For applications that need to do other work between frames (network polling, background processing, etc.), use `start()` + `tick()` instead of `run()`:

```zig
var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
defer program.deinit();

try program.start();
while (program.isRunning()) {
    try program.tick();
    // poll sockets, process jobs, etc.
}
```

### Debug logging

Since stdout is owned by the renderer, use file-based logging:

```zig
// In your update function, log via context:
pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
    ctx.log("received key: {s}", .{@tagName(msg)});
    // ...
}
```

### Message filtering

Intercept and transform messages before they reach your model:

```zig
var program = zz.Program(Model).init(init.gpa, init.io, init.environ_map);
program.setFilter(&myFilter);

fn myFilter(msg: Model.Msg) ?Model.Msg {
    // Return null to drop the message, or modify it
    return msg;
}
```

## Terminal features

### Bracketed paste

Handle pasted text as a single event by adding a `paste` field to your Msg:

```zig
pub const Msg = union(enum) {
    key: zz.KeyEvent,
    paste: []const u8,  // Receives full pasted text
};
```

A paste arrives as one event. Very large pastes (beyond the parser's internal
buffer) stream in as several consecutive `paste` events instead, split only on
codepoint boundaries — append them rather than replacing.

### Parsing terminal input yourself

`zz.InputParser` is the decoder the runtime uses, exposed for custom input
loops. It matters because terminals do not deliver whole sequences: a read
lands wherever the kernel had bytes ready, so an SGR mouse report is routinely
cut in half during fast scrolling. Parsing each read on its own turns the
leading `ESC` into an Escape key press and spills the remaining bytes into the
application as text.

```zig
var parser: zz.InputParser = .{};

// Every loop iteration, including the ones that read nothing — a lone ESC is
// only released once `escape_timeout_ns` has passed without more input.
const n = try terminal.readInput(&buf, 0);
const events = try parser.feed(allocator, buf[0..n], now_ns);
for (events) |event| switch (event) {
    .key => |k| ...,
    .mouse => |m| ...,
    .none => {},
};
```

Terminal replies that are not key presses (device attributes, cursor position
reports, OSC clipboard answers, Kitty graphics acknowledgements) are consumed
and discarded rather than surfacing as text.

For a buffer that is known to be complete — a test fixture, a recorded
session — `zz.input.keyboard.parseAll` decodes it in one call without any
retained state.

### OSC 52 clipboard

Copy text/bytes to the system clipboard from your app:

```zig
// Uses Program option defaults (.osc52)
_ = try ctx.setClipboard("Copied from ZigZag");
```

Query clipboard bytes back from the terminal:

```zig
if (try ctx.getClipboard(ctx.allocator)) |clip| {
    // clip is decoded bytes from OSC 52 response
}
```

Per-call overrides for edge cases:

```zig
_ = try ctx.setClipboardWithOptions("Primary selection", .{
    .target = .primary,
    .terminator = .st,
    .passthrough = .tmux,
    .max_bytes = 64 * 1024,
});

if (try ctx.getClipboardWithOptions(ctx.allocator, .{
    .target = .clipboard,
    .timeout_ms = 250,
    .passthrough = .auto,
    .strict_target = true,
})) |clip| {
    _ = clip;
}
```

Advanced/extension example (non-standard selector string):

```zig
_ = try ctx.setClipboardWithOptions("Custom selector", .{
    .target = .{ .raw = "c" },
});
```

Notes:
- Returns `false` when disabled (`.osc52.enabled = false`), blocked by guardrails (TTY/size), or unavailable in current output mode.
- Query returns `null` when disabled/blocked/timed out/no response/invalid payload.
- `.passthrough = .auto` detects tmux/screen-like environments and wraps OSC 52 in DCS passthrough when needed.
- Terminals differ in security policy and maximum accepted sequence length. Use `.max_bytes` to enforce an app-side ceiling if desired.
- The `run-clipboard_osc52` example also handles `Msg.paste` (bracketed paste input) to demonstrate inbound paste events.

### Suspend and resume

Ctrl+Z support is enabled by default. Handle resume events by adding a `resumed` field:

```zig
pub const Msg = union(enum) {
    key: zz.KeyEvent,
    resumed: void,  // Sent after process resumes from Ctrl+Z
};
```

### Images

Image commands are automatically no-ops on unsupported terminals. All `draw*` functions return `bool` indicating success.

#### Basic usage

```zig
// Draw from file (auto-selects best protocol)
if (ctx.supportsImages()) {
    _ = try ctx.drawImageFromFile("assets/cat.png", .{
        .width_cells = 40,
        .height_cells = 20,
    });
}

// Draw from file with specific protocol
_ = try ctx.drawImageFromFileWithProtocol("assets/cat.png", .{
    .width_cells = 40,
    .z_index = -1,  // Behind text (Kitty only)
}, .kitty);
```

#### In-memory image data

Render raw pixels or PNG bytes directly from memory, without writing to disk:

```zig
// Draw PNG bytes from memory
_ = try ctx.drawImageData(png_bytes, .{
    .format = .png,
    .width_cells = 20,
    .height_cells = 10,
});

// Draw raw RGBA pixels
_ = try ctx.drawImageData(rgba_pixels, .{
    .format = .rgba,
    .pixel_width = 100,   // Required for RGB/RGBA
    .pixel_height = 100,
    .width_cells = 20,
});
```

#### Image caching with Kitty

Transmit an image once, display it many times without re-uploading:

```zig
// Upload to cache (no display)
_ = try ctx.transmitKittyImageFromFile("assets/logo.png", .{
    .image_id = 1,
});

// Display cached image at different positions
_ = try ctx.placeKittyImage(.{
    .image_id = 1,
    .width_cells = 10,
    .height_cells = 5,
});

// Clean up when done
_ = try ctx.deleteKittyImage(.{ .by_id = 1 });
_ = try ctx.deleteKittyImage(.all);  // Delete everything
```

#### Z-index and Unicode placeholders with Kitty

```zig
// Render image behind text
_ = try ctx.drawKittyImageFromFile("assets/bg.png", .{
    .z_index = -1,            // Negative = behind text
    .unicode_placeholder = true, // Image participates in text reflow/scrolling
});
```

#### Protocol override

Force a specific protocol instead of auto-selection (Kitty > iTerm2 > Sixel):

```zig
_ = try ctx.drawImageFromFileWithProtocol("image.png", .{}, .iterm2);
_ = try ctx.drawImageDataWithProtocol(data, .{ .format = .png }, .sixel);
```

#### Querying capabilities

```zig
const caps = ctx.getImageCapabilities();
// caps.kitty_graphics: bool
// caps.iterm2_inline_image: bool
// caps.sixel: bool

if (ctx.supportsKittyGraphics()) { /* ... */ }
if (ctx.supportsIterm2InlineImages()) { /* ... */ }
if (ctx.supportsSixel()) { /* ... */ }
```

#### Command-based API

All image operations are also available as commands from `update()`:

```zig
// File image with all options
return .{ .image_file = .{
    .path = "assets/cat.png",
    .placement = .center,
    .width_cells = 40,
    .protocol = .auto,     // .auto, .kitty, .iterm2, .sixel
    .z_index = -1,         // Behind text (Kitty)
    .unicode_placeholder = true,  // Text reflow (Kitty)
} };

// In-memory data
return .{ .image_data = .{
    .data = png_bytes,
    .format = .png,        // .rgb, .rgba, .png
    .width_cells = 20,
} };

// Cache + place workflow
return .{ .batch = &.{
    .{ .cache_image = .{ .source = .{ .file = "logo.png" }, .image_id = 1 } },
    .{ .place_cached_image = .{ .image_id = 1, .placement = .center } },
} };

// Delete cached images
return .{ .delete_image = .{ .by_id = 1 } };
return .{ .delete_image = .all };
```

#### Detection

Detection combines runtime protocol probes with terminal feature/env hints:
- Kitty graphics: Kitty query command (`a=q`) for confirmation.
- iTerm2 inline images: `OSC 1337;Capabilities`/`TERM_FEATURES` when available.
- Sixel: iTerm/WezTerm `TERM_FEATURES` (`Sx`) and primary device attributes (`CSI c`, param `4`).

Common terminals supported by default:
- Kitty and Ghostty via Kitty graphics protocol.
- iTerm2 and WezTerm via `OSC 1337` inline images.
- Sixel-capable terminals (for example xterm with Sixel, mlterm, contour).

#### Notes

- File paths are validated before sending; missing files return `false` instead of erroring.
- For iTerm2, large images (>750KB encoded) are sent with multipart `OSC 1337` sequences automatically.
- For Sixel, provide a `.sixel`/`.six` file or a regular image with `img2sixel` in `PATH`. Optional `-w`/`-h` pixel hints are passed through.
- Inside multiplexers (tmux/screen/zellij), image passthrough depends on multiplexer configuration.
- Image caching, z-index, and unicode placeholders are Kitty-specific features; they are silently ignored on other protocols.

## Layout utilities

### Join

Combine multiple strings:

```zig
// Horizontal (side by side)
const row = try zz.joinHorizontal(allocator, &.{ left, middle, right });

// Vertical (stacked)
const col = try zz.joinVertical(allocator, &.{ top, middle, bottom });
```

### Measure

Get text dimensions (ANSI-aware):

```zig
const w = zz.width("Hello");           // 5
const h = zz.height("Line 1\nLine 2"); // 2
```

### Place

Position content in a bounding box:

```zig
// 2D placement in a bounding box
const centered = try zz.place.place(allocator, 80, 24, .center, .middle, content);

// Single-axis horizontal placement
const right_aligned = try zz.placeHorizontal(allocator, 80, .right, content);

// Single-axis vertical placement
const bottom_aligned = try zz.placeVertical(allocator, 24, .bottom, content);

// Float-based positioning (0.0 = left/top, 0.5 = center, 1.0 = right/bottom)
const placed = try zz.placeFloat(allocator, 80, 24, 0.75, 0.25, content);
```
