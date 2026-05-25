# godot-pixel-tree

Godot editor plugin for GDScript 4.6+ that adds a `PixelTree` node for quickly generating pixel-art trees.

## What it does

This plugin recreates the attached Tiny Trees HTML/JS generator inside Godot:

- five presets: `Oak`, `Sakura`, `Palm`, `Oak Winter`, `Birch`
- deterministic generation from a seed
- one-click regeneration in the Inspector
- live preview directly in the 2D editor
- pixel-based branch and leaf rendering with lightweight falling particles

## Usage

1. Enable the `PixelTree` plugin in `Project > Project Settings > Plugins`.
2. Add a `PixelTree` node to your scene.
3. Adjust `canvas_size`, `tree_preset`, `seed`, and `preview_scale`.
4. Toggle `generate_now` in the Inspector whenever you want a fresh tree.

## Example

- Open [example/example_forest.tscn](/Users/dustni/workspace/godot/godot-pixel-tree/example/example_forest.tscn) to see a simple showcase scene built with the addon.

## Notes

- The node is implemented as `Node2D` and draws an internally generated texture.
- `randomize_on_each_regenerate` ignores the fixed seed and creates a new variation each time.
- `get_tree_image()` and `get_tree_texture()` are available if you want to reuse the generated result in your own tools.
