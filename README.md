# Hex picker

Fullscreen honeycomb overlay for [Omarchy](https://omarchy.org/). Pick installed themes, the current theme’s backgrounds, or install from the [bjarneo/omarchy-themes](https://bjarneo.github.io/omarchy-themes/) gallery (~3,000 themes).

Does not replace Omarchy’s stock theme/background switchers. Bind it to whatever keys you want.

## Install

```sh
omarchy plugin add https://github.com/rblalock/omarchy-hex-picker.git --enable
```

Then add binds in `~/.config/hypr/bindings.lua` (stock Omarchy keys stay as they are):

```lua
o.bind("SUPER + ALT + T", "Hex theme picker", "omarchy-shell shell summon rblalock.hex-picker '{\"mode\":\"themes\"}'")
o.bind("SUPER + ALT + B", "Hex background picker", "omarchy-shell shell summon rblalock.hex-picker '{\"mode\":\"backgrounds\"}'")
```

Optional: skip compositor layer fades so the overlay’s own motion is the only animation.

```lua
hl.layer_rule({ match = { namespace = "^omarchy-hex-picker$" }, no_anim = true, animation = "none" })
```

```sh
omarchy-shell shell rescanPlugins
```

## Use

| Input | Action |
| --- | --- |
| `Super+Alt+T` | Open installed themes |
| `Super+Alt+B` | Open backgrounds for the current theme |
| `Tab` | Cycle **Themes → Backgrounds → Gallery** |
| Type | Filter |
| `Enter` | Apply, or install from the gallery |
| Right-click | Delete a **user-installed** theme |
| `Delete` | Same, on the selected user theme |
| `Esc` | Close |

Gallery install writes a normal Omarchy user theme under `~/.config/omarchy/themes/<slug>/` and runs `omarchy theme set`. After that it shows up on the Themes tab.

The gallery index (~35MB once, then a 24h cache) and thumbs live in `~/.cache/omarchy/hex-picker/`. First visit warms thumbs in the background; later visits read from disk.

## Remove

```sh
omarchy plugin remove rblalock.hex-picker --yes
```

User themes you installed from the gallery stay until you remove them with `omarchy theme remove <slug>` or right-click Delete in the picker. Cache:

```sh
rm -rf ~/.cache/omarchy/hex-picker
```

## Validate

```sh
omarchy plugin validate .
```

## Credits

- [Omarchy](https://omarchy.org/) / Quickshell overlay contract
- Theme catalog and media: [bjarneo/omarchy-themes](https://github.com/bjarneo/omarchy-themes)
- Download hardening and apply path adapted from [gotar/omarchy-themes](https://github.com/gotar/omarchy-themes) (MIT)

Wallpapers remain under their original licenses as provided by that collection.
