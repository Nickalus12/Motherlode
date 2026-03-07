# Flame Touch Input Research

## How DragCallbacks Works in Flame

### Game-Level vs Component-Level Drag Handling

In Flame, `DragCallbacks` is a mixin that can be applied to **both** individual components and the game class itself.

**Component-level behavior:** When `DragCallbacks` is on a `PositionComponent`, the framework checks `containsLocalPoint()` to determine if the touch is within the component's bounds. Only if the touch point falls inside the component does it receive `onDragStart`.

**Game-level behavior:** When `DragCallbacks` is on the `Game` class (as in our `MotherlodeGame`), the game acts as a catch-all -- it receives **all** drag events regardless of position. This is the correct approach for our use case (virtual joystick-style directional zones).

**Conflict potential:** If both the game AND a child component have `DragCallbacks`, the event is delivered to the **topmost component first**. The event will NOT propagate to the game unless `event.continuePropagation = true` is set on the child component. In our case, **no child components have DragCallbacks**, so the game receives all events. No conflict here.

---

## Event Properties Available

### DragStartEvent
- `devicePosition` - coordinates in the device's coordinate system
- `canvasPosition` - coordinates in the game widget's coordinate system
- `localPosition` - coordinates in the component's local coordinate system
- `pointerId` - unique identifier for this touch pointer

### DragUpdateEvent
- `devicePosition` - device coordinates
- `canvasPosition` - canvas coordinates (always valid, even if finger moves off-component)
- `localPosition` - local coordinates (**can be NaN if finger moves off-component**)
- `delta` - movement delta since last update (canvas-relative)
- `localDelta` - movement delta in local coordinates
- `timestamp` - time elapsed since drag start
- `pointerId` - touch pointer identifier
- **NOTE: There is NO `canvasStartPosition` property** (see bug below)

### DragEndEvent
- `pointerId` - touch pointer identifier
- (No position data on end events)

---

## BUGS FOUND IN PROJECT CODE

### Bug 1: `event.canvasStartPosition` does not exist on DragUpdateEvent (CRITICAL)

**File:** `D:\Projects\Motherlode\lib\motherlode_game.dart`, line 201

```dart
// CURRENT (BROKEN):
@override
void onDragUpdate(DragUpdateEvent event) {
  super.onDragUpdate(event);
  if (!pod.isMounted) return;
  podController.handleTouchMove(
    event.pointerId,
    event.canvasStartPosition,  // <-- THIS PROPERTY DOES NOT EXIST
  );
}
```

`DragUpdateEvent` has these position properties:
- `canvasPosition` (current position of the finger)
- `devicePosition` (current position in device coords)
- `localPosition` (current position in local coords, can be NaN)
- `delta` / `localDelta` (movement since last event)

There is **no** `canvasStartPosition`. This will either:
1. Cause a compile error (most likely), or
2. Return null/zero if there's a dynamic fallback

**Fix:** Change to `event.canvasPosition` to get the **current** touch position during drag:

```dart
@override
void onDragUpdate(DragUpdateEvent event) {
  super.onDragUpdate(event);
  if (!pod.isMounted) return;
  podController.handleTouchMove(
    event.pointerId,
    event.canvasPosition,  // FIXED: use current canvas position
  );
}
```

### Bug 2: Coordinate space mismatch between canvasPosition and game.size

**File:** `D:\Projects\Motherlode\lib\entities\pod\pod_controller.dart`, lines 70-76

The `_updateTouchInput()` method uses `game.size` as the viewport size and divides touch coordinates by it:

```dart
final viewportSize = game.size;
final centerX = viewportSize.x / 2;
final centerY = viewportSize.y / 2;

for (final touch in _activeTouches.values) {
  final relX = touch.x / viewportSize.x;  // expects 0..1 range
  final relY = touch.y / viewportSize.y;  // expects 0..1 range
```

**The `canvasPosition` from DragStartEvent/DragUpdateEvent is in the game widget's canvas coordinate system.** The `game.size` property returns the canvas size in logical pixels. So `canvasPosition` values range from `(0,0)` to `(game.size.x, game.size.y)`.

**This is actually correct** -- dividing `canvasPosition` by `game.size` gives values in the 0..1 range as expected. The coordinate spaces match.

However, note that `game.size` on a `Forge2DGame` returns the **viewport size in world units** (meters), not pixels, because Forge2D applies a zoom. If the zoom is set to `GameConstants.pixelsPerMeter`, then `game.size` returns `(screenWidth / zoom, screenHeight / zoom)` in world-space meters, while `canvasPosition` is in **pixel-space**.

**This IS a coordinate mismatch.** The `canvasPosition` is in canvas pixels (e.g., 0..400), but `game.size` in a Forge2DGame returns world-space dimensions (e.g., 0..20 if zoom is 20). Dividing pixel position by world size gives nonsensical ratios.

**Fix:** Use `camera.viewport.size` instead of `game.size` to get the viewport dimensions in the same coordinate space as `canvasPosition`:

```dart
// In _updateTouchInput():
final viewportSize = game.camera.viewport.size;  // pixels, matches canvasPosition
```

Alternatively, use `game.canvasSize` if available, which returns the canvas dimensions in logical pixels.

### Bug 3 (Minor): Unused relX/relY variables computed but only used for corner detection

Lines 75-76 compute `relX` and `relY`, but the primary direction logic (lines 79-97) uses absolute pixel distances (`dx`, `dy`). The `relX`/`relY` are only used for the corner-combo detection (lines 100-106). This is not a bug per se, but the corner detection thresholds (0.3, 0.7) will be wrong if the coordinate mismatch from Bug 2 exists.

---

## SUMMARY OF REQUIRED FIXES

| Priority | File | Line | Issue | Fix |
|----------|------|------|-------|-----|
| CRITICAL | `motherlode_game.dart` | 201 | `canvasStartPosition` does not exist on `DragUpdateEvent` | Change to `event.canvasPosition` |
| HIGH | `pod_controller.dart` | 70 | `game.size` returns world-space units in Forge2DGame, not canvas pixels | Use `game.camera.viewport.size` instead |

### Recommended Code Changes

**motherlode_game.dart** -- Fix onDragUpdate:
```dart
@override
void onDragUpdate(DragUpdateEvent event) {
  super.onDragUpdate(event);
  if (!pod.isMounted) return;
  podController.handleTouchMove(
    event.pointerId,
    event.canvasPosition,  // was: event.canvasStartPosition (nonexistent)
  );
}
```

**pod_controller.dart** -- Fix viewport size source:
```dart
void _updateTouchInput() {
  // Reset all inputs
  pod.thrustUp = false;
  pod.thrustLeft = false;
  pod.thrustRight = false;
  pod.drillDown = false;

  final viewportSize = game.camera.viewport.size;  // was: game.size (world units)
  final centerX = viewportSize.x / 2;
  final centerY = viewportSize.y / 2;
  // ... rest unchanged
}
```
