# hexdump.yazi

A Yazi previewer that renders any file as a classic `hexdump -C` style dump,
coloured by byte class. Output is byte-for-byte identical to `hexdump -C` at 16
columns, except that the ASCII gutter is padded so the closing `|` stays aligned
on a short final row.

No external dependencies — it reads the file through Yazi's own `fs.access()`
API and formats in Lua.

Requires Yazi 26.9.1 or newer.

## Install

```sh
ya pkg add <you>/hexdump
```

Or link a working copy straight into your plugins directory:

```sh
ln -s "$PWD" ~/.config/yazi/plugins/hexdump.yazi
```

## Configure

Previewer rules live under `[plugin]` in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
	{ mime = "application/octet-stream", run = "hexdump" },
	{ mime = "application/x-{executable,sharedlib,mach-binary}", run = "hexdump" },
]

append_previewers = [
	# A wildcard `url` rule here replaces Yazi's default `file` fallback.
	{ url = "*", run = "hexdump" },
]
```

Options are passed as arguments on `run`, **per rule** — they apply only to the
rule that matches, so a binary caught by `prepend_previewers` ignores anything
set on the wildcard fallback:

| Argument     | Default  | Meaning                                       |
| ------------ | -------- | --------------------------------------------- |
| `--columns`  | `auto`   | Bytes per row, or `auto` to fill the pane.    |
| `--group`    | `8`      | Insert a gap every N bytes.                   |

```toml
{ mime = "application/octet-stream", run = "hexdump --columns=16 --group=4" }
```

`auto` picks the widest of 64 / 32 / 16 / 12 / 8 / 4 columns that fits the
**preview pane** — not the terminal. A row costs
`4 * columns + ceil(columns / group) + 12` cells, which at the default
`--group=8` means:

| Columns | Needs a pane of |
| ------- | --------------- |
| 4       | 29              |
| 8       | 45              |
| 12      | 62              |
| 16      | 78              |
| 32      | 144             |
| 64      | 276             |

At Yazi's default `ratio = [1, 4, 3]` the preview pane is only 3/8 of the
terminal, so a conventional 16-column dump needs a terminal about 208 cells
wide. If you want 16 columns on a normal terminal, give the preview more room:

```toml
[mgr]
ratio = [ 1, 3, 4 ]   # or [ 0, 3, 5 ] to drop the parent pane entirely
```

Forcing `--columns` wider than the pane is allowed: the ASCII gutter is dropped
rather than clipped off mid-cell, so you still get complete hex rows.

## Colours

Bytes are sorted into six classes, each with a default colour:

| Class      | Bytes                        | Default    |
| ---------- | ---------------------------- | ---------- |
| `frame`    | offsets, padding, gutter     | dark gray  |
| `null`     | `0x00`                       | dark gray  |
| `white`    | space, `\t \n \v \f \r`      | green      |
| `ascii`    | printable ASCII              | cyan       |
| `ctrl`     | other ASCII control bytes    | magenta    |
| `nonascii` | `>= 0x80`                    | yellow     |

The defaults are ratatui colour names, so they resolve through your terminal's
16-colour palette. Override any subset from a `[hexdump]` section in your
`theme.toml` or `flavor.toml`:

```toml
[hexdump]
ascii    = { fg = "cyan" }
nonascii = { fg = "#e5c07b", bold = true }
```

Anything you leave out keeps its default.

Styles are resolved each time the preview is drawn, not cached at load, so a
theme change shows up as soon as Yazi itself reloads the theme — either by
restarting, or with the `app:theme` action, which has no default binding:

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on  = "<C-t>"
run = "app:theme"
```

Editing `theme.toml` alone is not enough: Yazi holds the parsed theme in
memory, so without one of those the preview keeps the old colours.

## Notes

The six byte classes are fixed. Their colours are themeable, but the boundaries
between them — which bytes count as `ctrl` rather than `white`, say — live in
`CLASS` in `main.lua` and need a code edit.

Yazi's `Fd` has no seek, so scrolling to offset N reads and discards N bytes.
`peek` clamps `skip` to the last full screen using `file.cha.len`, which bounds
that read by the file size; in practice you cannot scroll far enough for it to
matter.
