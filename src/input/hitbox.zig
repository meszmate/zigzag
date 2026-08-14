//! Hit testing utilities for mouse interactions.
//! Provides rectangular region hit detection for UI components.

const mouse = @import("mouse.zig");
const MouseEvent = mouse.MouseEvent;

/// A rectangular region for mouse hit testing.
pub const HitBox = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Create a hit box at the given position and size.
    pub fn init(x: u16, y: u16, w: u16, h: u16) HitBox {
        return .{ .x = x, .y = y, .width = w, .height = h };
    }

    /// Check whether a mouse event falls within this region.
    pub fn contains(self: HitBox, event: MouseEvent) bool {
        return event.x >= self.x and
            event.x < self.x +| self.width and
            event.y >= self.y and
            event.y < self.y +| self.height;
    }

    /// Check whether a coordinate falls within this region.
    pub fn containsPoint(self: HitBox, x: u16, y: u16) bool {
        return x >= self.x and
            x < self.x +| self.width and
            y >= self.y and
            y < self.y +| self.height;
    }

    /// Check if a click event (press with left button) occurred in this region.
    pub fn clicked(self: HitBox, event: MouseEvent) bool {
        return event.button == .left and
            event.event_type == .press and
            self.contains(event);
    }

    /// Check if a right-click occurred in this region.
    pub fn rightClicked(self: HitBox, event: MouseEvent) bool {
        return event.button == .right and
            event.event_type == .press and
            self.contains(event);
    }

    /// Get local coordinates relative to the hit box origin.
    /// Returns null if the event is outside the region.
    pub fn localCoords(self: HitBox, event: MouseEvent) ?struct { x: u16, y: u16 } {
        if (!self.contains(event)) return null;
        return .{
            .x = event.x - self.x,
            .y = event.y - self.y,
        };
    }

    /// Expand the hit box by a padding amount on all sides.
    pub fn expand(self: HitBox, padding: u16) HitBox {
        return .{
            .x = self.x -| padding,
            .y = self.y -| padding,
            .width = self.width +| padding *| 2,
            .height = self.height +| padding *| 2,
        };
    }

    /// Check if two hit boxes overlap.
    pub fn overlaps(self: HitBox, other: HitBox) bool {
        return self.x < other.x +| other.width and
            self.x +| self.width > other.x and
            self.y < other.y +| other.height and
            self.y +| self.height > other.y;
    }
};

/// Track mouse state across frames (hover, pressed, etc.)
pub const MouseState = struct {
    hover: bool = false,
    pressed: bool = false,
    last_x: u16 = 0,
    last_y: u16 = 0,

    /// Update state from a mouse event against a hit box.
    /// Returns which interaction occurred.
    pub fn update(self: *MouseState, hitbox: HitBox, event: MouseEvent) Interaction {
        self.last_x = event.x;
        self.last_y = event.y;

        const inside = hitbox.contains(event);
        const was_hover = self.hover;
        self.hover = inside;

        if (event.event_type == .press and event.button == .left and inside) {
            self.pressed = true;
            return .press;
        }

        if (event.event_type == .release and event.button == .left) {
            if (self.pressed and inside) {
                self.pressed = false;
                return .click;
            }
            self.pressed = false;
        }

        // Wheel events are checked before the boundary crossing: a trackpad
        // reports movement and scrolling in the same event, and returning
        // `enter` there would drop the scroll entirely. The crossing is still
        // visible to the caller as `self.hover`.
        if (inside and event.button == .wheel_up) return .scroll_up;
        if (inside and event.button == .wheel_down) return .scroll_down;

        if (inside and !was_hover) return .enter;
        if (!inside and was_hover) return .leave;
        if (inside and event.event_type == .move) return .hover;

        return .none;
    }
};

pub const Interaction = enum {
    none,
    press,
    click,
    enter,
    leave,
    hover,
    scroll_up,
    scroll_down,
};
