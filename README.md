# godot-pixel-tree

Godot editor plugin for GDScript 4.6+ that adds a `PixelTree` node for quickly generating pixel-art trees.

## What it does

This plugin brings a pixel tree generator workflow into Godot.

- five presets: `Oak`, `Sakura`, `Palm`, `Oak Winter`, `Birch`
- deterministic generation from a seed
- one-click regeneration in the Inspector
- live preview directly in the 2D editor
- pixel-based branch and leaf rendering

## Usage

1. Enable the `PixelTree` plugin in `Project > Project Settings > Plugins`.
2. Add a `PixelTree` node to your scene.
3. Place the node where you want the tree root to be, then adjust `tree_preset`, `seed`, and `preview_scale`.
4. Toggle `generate_now` in the Inspector whenever you want a fresh tree.

## Example

- Open [example/example_forest.tscn](/Users/dustni/workspace/godot/godot-pixel-tree/example/example_forest.tscn) to see a simple showcase scene built with the addon.

## Notes

- The node is implemented as `Node2D`, and its transform origin is the tree root.
- `randomize_on_each_regenerate` ignores the fixed seed and creates a new variation each time.
- `get_tree_image()` and `get_tree_texture()` are available if you want to reuse the generated result in your own tools.

## Acknowledgements

This project was inspired by Matouš Marek's [Pixelart tree generator](https://showcase.fmk.utb.cz/en/digital-design/pixelart-tree-generator/).

Thanks to Matouš Marek for the original idea and inspiration.
