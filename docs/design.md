# Design notes

## Track generation

Each circuit is a closed control polygon in `TrackData`. `TrackBuilder` runs
Chaikin corner cutting over it, which stays inside the convex hull of the
polygon. That property is what guarantees the generated centreline can never
self-intersect, so checkpoint ordering and the AI racing line stay valid for
every layout.

The result is resampled to an even 4 m spacing. Every downstream system —
checkpoints, curvature, the AI, distance lookups — indexes into that single
array, so there is exactly one parameterisation of a circuit.

## Racing line

The racing line shares the centreline's parameterisation: same sample count,
same indices. Each sample is displaced sideways by an amount proportional to
the local curvature, cutting toward the inside of a bend and staying on the
centreline down the straights.

Building it as an independent resample is a trap. Index `N` of the racing line
then refers to a different point of the circuit than index `N` of the
centreline, and the AI steers off the road. An earlier version of this code did
exactly that, and the AI drove into the scenery.

The cut is deliberately capped at 1.4 m. A line that reaches the kerb leaves no
margin for the AI's tracking error, and the car scrapes the barrier through
every corner instead of completing laps.

## Car physics

Cars are `RigidBody3D` nodes, but almost none of the handling comes from the
engine's contact solver:

- The body's `PhysicsMaterial` friction is set to `0.02`. At the default of
  `1.0` the contact friction silently eats most of the engine force and caps the
  car far below its top speed.
- Longitudinal drive is a central force with a torque curve that tapers as the
  car approaches its top speed, plus drag and rolling resistance.
- Lateral grip is a decay rate applied as `force = mass * accel`, which makes
  the behaviour independent of the car's mass.
- Steering authority falls off with speed so the car stays controllable at
  200 km/h instead of snapping into a spin.

Grounding comes from a `RayCast3D` that starts above the roof and casts down
past the wheels, so it cannot start level with the road surface.

## Gearbox

`GEAR_RATIOS` are gearbox ratios only, and the revs are derived from wheel speed
times ratio. Automatic shifting upshifts near the limiter and downshifts when
the revs drop. A manual override is available through `shift_up` /
`shift_down`.

## AI driver

The AI never teleports. Each physics tick it advances a tracked sample index
along the racing line, picks a look-ahead point, and steers toward it.

Corner speed comes from the tyre's lateral grip limit: `v = sqrt(a_lat / k)`,
where `k` is the track curvature in radians per metre. The AI scans far enough
ahead to cover its own braking distance, so it starts slowing before the corner
rather than at the apex.

Two recovery behaviours keep a race from stalling:

- **Wall avoidance** nudges the car back toward the centre of the road and lifts
  off the power when it drifts toward the barrier.
- **Off-road recovery** takes over entirely when the car is past the kerb, and
  steers straight back to the nearest point of road. Without it, the AI would
  drive at a look-ahead point that lies across a barrier and circle the infield
  forever.

Both use the AI's own tracked index, never a global nearest-point search. Where
a circuit passes close to itself, a global search can snap onto the wrong
straight and the AI then fights a phantom wall.

## Lap tracking

Twelve `Area3D` gates, index 0 being the start/finish line. The gates mask
physics layer 2, which is where cars live.

Progress is a strict ordered chain: a gate only counts when its index equals the
car's expected next index. The finish line only counts when the whole chain is
complete. This is what stops reversing or loitering from advancing the lap
counter. Repeats of the *same* gate within 400 ms are debounced, because a car
sliding along a trigger can emit several `body_entered` events.

`LapTracker` owns the authoritative lap state and writes it back into each
`Car`, so the HUD can read `car.best_lap` and `car.current_lap` directly.

## Networking

`Net` is an autoload wrapping Godot's high-level multiplayer API. The host is
authoritative: it simulates every car and broadcasts a compact state payload
(`p` position, `y` yaw, `v` velocity, `g` gear, `r` rpm, `d` drifting) to the
clients, which interpolate between snapshots. Remote cars reject local control
input so a client cannot fight the host's state.

## Testing

`tools/validate.gd` is a static pass: it parses every script, loads every scene
and checks that resource references, input actions, RPC annotations and
`class_name` declarations all resolve.

`scripts/tools/TestHarness.gd` is the runtime pass. It builds real tracks and
checks geometry (length, spacing, no self-intersection, checkpoint ordering,
collision presence), exercises the lap rules against a scripted sequence of gate
crossings, round-trips the network payload, and then simulates a real race with
an AI driver at the wheel for 150 seconds.
