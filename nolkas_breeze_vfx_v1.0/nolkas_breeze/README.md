# Nolka's breeze VFX

​A 3D wind line / wind gust VFX for Godot, that may be used
for global environment effects or local air effects. 

## Content

### Generic

There are two generic effects, stored in `./vfx/base/`:

- Wind: base wind lines effect.
- Debris: base wind debris effect.

### Premade

All premade effects are stored in the `./vfx/premade` folder. They are showcased in the `demo.tscn` scene.

- Breeze
- Leaves in wind
- Blizzard
- Sandstorm
- Fire wind
- Electric wind

## Usage

All effect can simply be dropped in the scene and their parameters adjusted.
Most notably the `area`, `particles_amount` (or `amount_ratio` for composites) and `speed_scale` parameters.

All effects may be moved and rotated and their emission will follow accordingly.

### Advanced

All effects are interfaced via controller scripts which inherit `NlkWeatherEmitter`:

- `NlkWindEmitter`: controller for a wind lines effects. 
- `NlkDebrisEmitter`: controller for a wind debris effects. 
- `NlkCompositeWindEmitter`: controller for a composite effects (composed of multiple emitters) 

To create / parametrize a new simple effect, create a new inherited scene from
the base wind or debris scenes, and tweak them to you liking.

For composite effects, create a new `Node3D` scene and add a `NlkCompositeWindEmitter` to it.
Then add the desired effects / emitters as children.

> [!NOTE]
> Feel free to use the resources located in `./internal/textures`

## Contact

Want more effects? Have a question or a problem? Let me know on itch.io or via these channels:

- [Bluesky](https://bsky.app/profile/nolkaloid.bsky.social)
- [nolkaloid@gmail.com](mailto:nolkaloid@gmail.com)
