# hexdump.yazi

[![test](https://github.com/mdiiorio/hexdump.yazi/actions/workflows/test.yml/badge.svg)](https://github.com/mdiiorio/hexdump.yazi/actions/workflows/test.yml)

A Yazi previewer that renders any file as a classic `hexdump -C` style dump,
coloured by byte class.

No external dependencies — it reads the file through Yazi's own `fs.access()`
API and formats in Lua.

Requires Yazi 26.9.1 or newer.

## Install

```sh
ya pkg add mdiiorio/hexdump
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
preview pane.

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
