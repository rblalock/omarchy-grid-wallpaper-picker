# Hex picker

Honeycomb overlay for [Omarchy](https://omarchy.org/). Pick installed themes, the current theme’s backgrounds, or install from the [bjarneo/omarchy-themes](https://bjarneo.github.io/omarchy-themes/) gallery.

## Install

```sh
omarchy plugin add https://github.com/rblalock/omarchy-hex-picker.git --enable
```

Then make it launchable without a custom key (pick one or both):

```sh
PLUGIN="$HOME/.config/omarchy/plugins/rblalock.hex-picker"
cp "$PLUGIN/rblalock.hex-picker.desktop" ~/.local/share/applications/
```

Search **Hex picker** in the Omarchy app launcher. To also put it under Style in the Omarchy menu, merge `omarchy-menu.jsonc` from the plugin into `~/.config/omarchy/extensions/omarchy-menu.jsonc`.

Optional keybinds in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Hex theme picker", "omarchy-shell shell summon rblalock.hex-picker '{\"mode\":\"themes\"}'")
o.bind("SUPER + ALT + B", "Hex background picker", "omarchy-shell shell summon rblalock.hex-picker '{\"mode\":\"backgrounds\"}'")
hl.layer_rule({ match = { namespace = "^omarchy-hex-picker$" }, no_anim = true, animation = "none" })
```

```sh
omarchy-shell shell rescanPlugins
```

## Usage

Summon:

```sh
omarchy-shell shell summon rblalock.hex-picker '{"mode":"themes"}'
```

| Input | Action |
| --- | --- |
| App launcher / Style → Hex picker | Open |
| `Tab` | Themes → Backgrounds → Gallery |
| Type | Filter |
| `Enter` | Apply, or install the default **Palette** variant from the gallery |
| Right-click (gallery) | Install **Palette / Warm / Cool / Material / Aether** |
| Right-click (user theme) | Delete (`omarchy theme remove`) |
| `Esc` | Close |

Gallery palettes are precomputed in the catalog (Aether already ran upstream). This plugin does not run Aether.

Installed gallery items become normal user themes under `~/.config/omarchy/themes/<slug>/`.

## Remove

```sh
omarchy plugin remove rblalock.hex-picker --yes
rm -f ~/.local/share/applications/rblalock.hex-picker.desktop
```

Gallery-installed themes stay until `omarchy theme remove <slug>`. Cache: `rm -rf ~/.cache/omarchy/hex-picker`.

## Validate

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" HexPicker.qml HexCell.qml
```

## Credits

- Omarchy / Quickshell overlay contract
- Catalog and media: [bjarneo/omarchy-themes](https://github.com/bjarneo/omarchy-themes)
- Download hardening and apply path adapted from [gotar/omarchy-themes](https://github.com/gotar/omarchy-themes) (MIT)

Wallpapers remain under their original licenses as provided by that collection.
