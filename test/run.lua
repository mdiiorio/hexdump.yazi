--- Regression tests for the hexdump previewer.
---
---   lua test/run.lua
---
--- Needs only a stock Lua 5.4+ interpreter; Yazi is stubbed out by harness.lua.

local dir = arg[0]:match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path

local H = require("harness")

-- 42 bytes covering every byte class, and not a multiple of 16 so the last
-- row is partial.
local SAMPLE = "\0\0\72\69\76\76\79\255\72\105\33\9\10\32\1\127"
	.. "\128\129\254\255\112\97\100\100\105\110\103\45\116\111\45\52"
	.. "\50\33\0\0\0\0\0\0\0\0"

-- Verbatim `hexdump -C` output for SAMPLE, minus its trailing offset line.
local EXPECTED = {
	"00000000  00 00 48 45 4c 4c 4f ff  48 69 21 09 0a 20 01 7f  |..HELLO.Hi!.. ..|",
	"00000010  80 81 fe ff 70 61 64 64  69 6e 67 2d 74 6f 2d 34  |....padding-to-4|",
	"00000020  32 21 00 00 00 00 00 00  00 00                    |2!........|",
}

local failures, count = {}, 0

local function check(name, got, want)
	count = count + 1
	if got ~= want then
		failures[#failures + 1] = ("%s\n     got: %s\n    want: %s"):format(name, tostring(got), tostring(want))
	end
end

local function peek(job, opts)
	local sink = H.stub(opts)
	local M = dofile(dir .. "/../main.lua")
	return H.peek(M, sink, job)
end

local path = H.fixture(SAMPLE)

-- Output must match `hexdump -C` exactly, short final row included. The one
-- intentional difference is that we pad the ASCII gutter so the closing `|`
-- stays aligned, so widen the expectation to match rather than trimming what
-- we produced -- that way the padding itself is asserted too.
local function pad_gutter(row, cols)
	local head, gutter = row:match("^(.*|)([^|]*)|$")
	if not head then
		return row
	end
	return head .. gutter .. string.rep(" ", cols - #gutter) .. "|"
end

do
	local s = peek { path = path, w = 80, h = 8, columns = 16 }
	for i, want in ipairs(EXPECTED) do
		check("row " .. i .. " matches hexdump -C", s.lines[i], pad_gutter(want, 16))
	end
	check("no extra rows", #s.lines, #EXPECTED)
end

-- `auto` sizes against the preview pane, widest of 64/32/16/12/8/4 that fits.
-- Needs a fixture at least as long as the widest row under test, or a short
-- file would cap the count and the assertion would pass for the wrong reason.
local wide = H.fixture(string.rep("\170\187\204\221", 32))

for _, case in ipairs { { 29, 4 }, { 45, 8 }, { 62, 12 }, { 78, 16 }, { 144, 32 }, { 276, 64 } } do
	local w, cols = case[1], case[2]
	local s = peek { path = wide, w = w, h = 1 }
	local hex = s.lines[1]:match("^%x+  (.-) |") or s.lines[1]
	local n = select(2, hex:gsub("%x%x", ""))
	check(("pane %d picks %d columns"):format(w, cols), n, cols)
	-- One cell narrower must drop to the next rung down.
	if w > 29 then
		local narrower = peek { path = wide, w = w - 1, h = 1 }
		local nhex = narrower.lines[1]:match("^%x+  (.-) |") or narrower.lines[1]
		check(("pane %d does not pick %d"):format(w - 1, cols), select(2, nhex:gsub("%x%x", "")) < cols, true)
	end
end

-- A forced width the pane cannot hold drops the gutter rather than clipping it.
do
	local s = peek { path = path, w = 59, h = 1, columns = 16 }
	check("over-wide forced columns drop the gutter", s.lines[1]:find("|", 1, true), nil)
	check("over-wide forced columns keep all 16 bytes", select(2, s.lines[1]:gsub("%x%x", "")) - 4, 16)
end

-- Offsets advance by the row width, and `skip` is in rows.
do
	local s = peek { path = path, w = 80, h = 2, skip = 1, columns = 16 }
	check("skip=1 starts at 0x10", s.lines[1]:sub(1, 8), "00000010")
end

-- Scrolling past the end is clamped back to the last full screen.
do
	local s = peek { path = path, w = 80, h = 2, skip = 99, columns = 16 }
	check("past EOF re-emits peek", s.emitted and s.emitted.action, "peek")
	check("past EOF clamps to last screen", s.emitted and s.emitted.args[1], 1)
	check("past EOF sets upper_bound", s.emitted and s.emitted.args.upper_bound, true)
	check("past EOF draws nothing", s.text, nil)
end

-- An empty file reports rather than rendering a blank pane.
do
	local s = peek { path = H.fixture(""), w = 80, h = 4 }
	check("empty file reports", s.msg, "Empty file")
end

-- A zero-height pane is a no-op, not an error.
do
	local s = peek { path = path, w = 80, h = 0 }
	check("zero-height pane draws nothing", s.text, nil)
end

-- Byte classes get their default colours when the theme says nothing.
do
	local s = peek { path = path, w = 80, h = 1, columns = 16 }
	check("null is dark gray", H.colour_of(s, "00 "), "darkgray")
	check("printable ASCII is cyan", H.colour_of(s, "48 45"), "cyan")
	check("high bytes are yellow", H.colour_of(s, "ff"), "yellow")
	check("offsets are dark gray", H.colour_of(s, "00000000"), "darkgray")
end

-- ...and a `[hexdump]` theme section overrides them per class, leaving the
-- rest on their defaults.
do
	local s = peek({ path = path, w = 80, h = 1, columns = 16 }, {
		th = { hexdump = { ascii = { color = "red" } } },
	})
	check("themed class is overridden", H.colour_of(s, "48 45"), "red")
	check("unthemed class keeps its default", H.colour_of(s, "ff"), "yellow")
end

H.cleanup()

if #failures == 0 then
	print(("ok — %d checks passed"):format(count))
	os.exit(0)
end
print(("FAILED — %d of %d checks"):format(#failures, count))
for _, f in ipairs(failures) do
	print("  - " .. f)
end
os.exit(1)
