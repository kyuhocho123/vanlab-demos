# Engine test scene — the same scene for every route

Purpose: answer two open unknowns before the engine is chosen (plan IDs U10 and U11).

- **U10**: how fast and how good does a 3D van scene feel on Kyu's Galaxy S26 Ultra in each route?
- **U11**: can an AI agent build, run and test the scene in that route without a person using an editor?

Every route builds this exact scene, so the results can be compared.

## The scene

- A test box, **not a real van**: interior 6.00 m long, 1.80 m wide, 1.90 m high (longer than a van on purpose, so there is free floor to drag across). Floor, front wall and two side walls; the rear and the roof are open so the camera can see in. Real van dimensions are still unverified (plan RQ4), so none are used.
- 12 floor items, each a plain box with a name, a colour and a size in metres:

| # | Name | Length | Width | Height |
|---|---|---|---|---|
| 1 | Bed platform | 1.90 | 1.40 | 0.50 |
| 2 | Galley | 1.20 | 0.55 | 0.90 |
| 3 | Fridge | 0.50 | 0.55 | 0.85 |
| 4 | Shower stall | 0.80 | 0.80 | 1.90 |
| 5 | Bench | 1.00 | 0.50 | 0.45 |
| 6 | Water tank | 0.80 | 0.40 | 0.40 |
| 7 | Battery box | 0.50 | 0.35 | 0.30 |
| 8 | Toilet | 0.40 | 0.45 | 0.45 |
| 9 | Closet | 0.60 | 0.55 | 1.80 |
| 10 | Table | 0.70 | 0.50 | 0.72 |
| 11 | Step | 0.40 | 0.30 | 0.20 |
| 12 | Drawer unit | 0.60 | 0.50 | 0.60 |

  The sizes are round test values, not product dimensions.

## What the player can do

1. **Move an item**: put a finger on it and drag. It must start moving on the first touch, with no tap-to-select step and no hold delay (this is the fix for audit defects B09 and B10). It slides on the floor, snaps to 5 cm, and cannot leave the box.
2. **See overlaps**: an item that overlaps another turns red while it overlaps.
3. **Look around**: one finger on empty space orbits the camera; two fingers pinch to zoom and drag to pan. If a pinch starts with one finger on an item, the item goes back to where it was and the camera zooms (added after Kyu's phone trial).
4. **Rotate** the selected item by 90 degrees with a button.
5. **Stress the scene**: a button adds 500 more boxes each press.
6. **Switch shadows** on and off, and switch between capped and full screen resolution.
7. **Reset**.

## What the scene reports on screen

Frames per second (average of the last 60 frames), the slowest frame in the last 2 seconds, draw calls, triangles, item count, the screen's pixel ratio and the ratio in use.

## What Kyu records per route (about 3 minutes)

1. Frames per second at the start, and how many boxes it takes before the number drops below the screen's top speed.
2. Does an item move on the first touch, every time? (yes / no)
3. Does the item stay under your finger, or lag behind? (under / lags)
4. Does orbiting ever grab an item by mistake, or the reverse? (never / sometimes / often)
5. Feel, 1 to 5.

## What the agent records per route

Hours of agent work, lines of code, whether the build ran with no editor window, whether an automated test could drive the scene, download size, and every place a human was needed.
