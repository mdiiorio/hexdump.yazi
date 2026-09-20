# Tests

```sh
lua test/run.lua
```

Needs only a stock Lua 5.4+ interpreter — `harness.lua` stubs out the parts of
the Yazi runtime that `main.lua` touches (`ui`, `ya`, `fs`, `th`, and the
`empty`/`code` plugins), so nothing here needs Yazi itself.

Exit status is 0 on success, 1 on failure, with a summary line either way.

## What's covered

| Area | Checks |
| ---- | ------ |
| Output format | Three rows compared against verbatim `hexdump -C` output, including a short final row |
| Column ladder | Each rung (4/8/12/16/32/64) at the pane width that admits it, plus a negative case one cell narrower |
| Narrow panes | A forced `--columns` wider than the pane drops the ASCII gutter instead of clipping it |
| Scrolling | `skip` is in rows; offsets advance by the row width |
| EOF | Scrolling past the end re-emits `peek` clamped to the last full screen, with `upper_bound` |
| Degenerate input | Empty file reports rather than drawing; zero-height pane is a no-op |
| Colours | Defaults per byte class, and a partial `[hexdump]` theme section overriding some classes while others keep their defaults |

## Two things the harness does on purpose

**`Fd:read()` returns at most 7 bytes per call.** The real one is a single
`read` syscall and can come back short; the refill loops in `main.lua` exist
to cope with that. A stub that always returned everything asked for would hide
a whole class of bug.

**`hexdump -C` rows are stored verbatim, and the expectation is widened to
match our padded gutter** rather than our output being trimmed down to match
the expectation. `pad_gutter()` in `run.lua` does that widening, so the padding
behaviour is asserted instead of normalised away.

## Confirming the tests can fail

Worth redoing after any substantial change — mutate `main.lua`, check the
suite notices, restore. These six were each caught:

| Mutation | Checks failed |
| -------- | ------------- |
| `%08x` → `%07x` in the address column | 6 |
| Drop `12` from `CANDIDATES` | 1 |
| Remove the EOF clamp | 1 |
| Drop the gutter padding on short rows | 1 |
| Ignore `th.hexdump` | 1 |
| Off-by-one on `skip` → byte offset | 9 |

## Packaging

Nothing in this directory reaches users. `ya pkg` copies `LICENSE`,
`README.md`, `main.lua`, any top-level kebab-case `*.lua`, and `assets/` — it
does not scan subdirectories. Note the "top-level" part: a `.lua` file left in
the repo root *would* ship.
