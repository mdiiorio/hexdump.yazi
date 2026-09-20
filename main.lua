--- @since 26.9.1
--- Hexdump previewer for Yazi: renders any file as a classic `hexdump -C`
--- style dump, with hexyl-ish colouring by byte class.

local M = {}

-- Colours per byte class. Accepts any ratatui colour name or "#rrggbb".
local PALETTE = {
	frame    = "darkgray", -- offset column, padding, the `|` gutters
	null     = "darkgray", -- 0x00
	white    = "green",    -- space, \t \n \v \f \r
	ascii    = "cyan",     -- printable ASCII
	ctrl     = "magenta",  -- other ASCII control bytes
	nonascii = "yellow",   -- >= 0x80
}

-- Column counts `--columns=auto` will try, widest first. 16/32/64 are the
-- conventional hexdump widths; 12 and below exist only so that a preview pane
-- too narrow for 16 still fills the space it has instead of falling back to 8.
local CANDIDATES = { 64, 32, 16, 12, 8, 4 }

-- Per-byte lookup tables, built once per Lua VM.
local HEX, COLOR, CHAR = {}, {}, {}
for b = 0, 255 do
	HEX[b] = string.format("%02x ", b)
	if b == 0 then
		COLOR[b], CHAR[b] = PALETTE.null, "."
	elseif b == 32 then
		COLOR[b], CHAR[b] = PALETTE.white, " "
	elseif b >= 9 and b <= 13 then
		COLOR[b], CHAR[b] = PALETTE.white, "."
	elseif b >= 33 and b <= 126 then
		COLOR[b], CHAR[b] = PALETTE.ascii, string.char(b)
	elseif b < 128 then
		COLOR[b], CHAR[b] = PALETTE.ctrl, "."
	else
		COLOR[b], CHAR[b] = PALETTE.nonascii, "."
	end
end

-- Width of one rendered row: offset + 2 spaces, the hex cells and their group
-- gaps, a space, then the `|...|` ASCII gutter.
local function row_width(cols, group) return 4 * cols + math.ceil(cols / group) + 12 end

--- Coalesces adjacent same-colour text into a single `ui.Span`.
local function builder()
	local spans, buf, cur = {}, {}, nil
	local function flush()
		if #buf > 0 then
			spans[#spans + 1] = ui.Span(table.concat(buf)):fg(cur)
			buf = {}
		end
	end
	return {
		add = function(text, color)
			if color ~= cur then
				flush()
				cur = color
			end
			buf[#buf + 1] = text
		end,
		done = function()
			flush()
			return spans
		end,
	}
end

--- @param addr integer Byte offset this row starts at
--- @param data string Buffer holding the bytes
--- @param from integer 1-based index of the row's first byte in `data`
--- @param n integer Number of bytes actually present in this row
--- @return Line
local function render_row(addr, data, from, n, cols, group, ascii)
	local b = builder()
	b.add(string.format("%08x  ", addr), PALETTE.frame)

	for i = 0, cols - 1 do
		if i < n then
			local byte = data:byte(from + i)
			b.add(HEX[byte], COLOR[byte])
		else
			b.add("   ", PALETTE.frame)
		end
		if (i + 1) % group == 0 and i + 1 < cols then
			b.add(" ", PALETTE.frame)
		end
	end

	if ascii then
		b.add(" |", PALETTE.frame)
		for i = 0, n - 1 do
			local byte = data:byte(from + i)
			b.add(CHAR[byte], COLOR[byte])
		end
		b.add(string.rep(" ", cols - n) .. "|", PALETTE.frame)
	end

	return ui.Line(b.done())
end

--- Reads and throws away `len` bytes, since `Fd` has no seek.
--- @return integer? skipped
--- @return Error?
local function discard(fd, len)
	local done = 0
	while done < len do
		local chunk, err = fd:read(math.min(len - done, 1048576))
		if not chunk then
			return nil, err
		elseif chunk == "" then
			break
		end
		done = done + #chunk
	end
	return done
end

--- `Fd:read()` is a single read syscall and may come back short.
--- @return string?
--- @return Error?
local function read_up_to(fd, len)
	local parts, got = {}, 0
	while got < len do
		local chunk, err = fd:read(math.min(len - got, 65536))
		if not chunk then
			return nil, err
		elseif chunk == "" then
			break
		end
		parts[#parts + 1] = chunk
		got = got + #chunk
	end
	return table.concat(parts)
end

function M.group(job)
	local n = tonumber(job.args and job.args.group)
	return n and n >= 1 and math.floor(n) or 8
end

function M.columns(job, group)
	local fixed = tonumber(job.args and job.args.columns)
	if fixed and fixed >= 1 then
		return math.floor(fixed)
	end
	for _, cols in ipairs(CANDIDATES) do
		if row_width(cols, group) <= job.area.w then
			return cols
		end
	end
	return CANDIDATES[#CANDIDATES]
end

function M:peek(job)
	local height = job.area.h
	if height < 1 then
		return
	end

	local group = M.group(job)
	local cols = M.columns(job, group)
	-- A forced `--columns` can overflow the pane. Drop the ASCII gutter rather
	-- than let it be clipped off mid-cell.
	local ascii = row_width(cols, group) <= job.area.w

	-- Clamp `skip` to the last full screen, so scrolling stops at EOF.
	local len = job.file.cha.len
	if len > 0 then
		local bound = math.max(0, math.ceil(len / cols) - height)
		if job.skip > bound then
			return ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
		end
	end

	local fd, err = fs.access():read(true):open(job.file.url)
	if not fd then
		return require("empty").msg(job, "Failed to open file: " .. tostring(err))
	end

	local offset = job.skip * cols
	local skipped, err = discard(fd, offset)
	local data
	if skipped then
		data, err = read_up_to(fd, cols * height)
	end
	ya.drop(fd)

	if not data then
		return require("empty").msg(job, "Failed to read file: " .. tostring(err))
	elseif #data == 0 then
		-- `len` lied (procfs and friends); back off to the start.
		if job.skip > 0 then
			return ya.emit("peek", { 0, only_if = job.file.url, upper_bound = true })
		end
		return require("empty").msg(job, "Empty file")
	end

	local lines = {}
	for i = 0, height - 1 do
		local from = i * cols + 1
		if from > #data then
			break
		end
		lines[#lines + 1] =
			render_row(offset + i * cols, data, from, math.min(cols, #data - from + 1), cols, group, ascii)
	end

	ya.preview_widget(job, ui.Text(lines):area(job.area))
end

function M:seek(job) require("code"):seek(job) end

return M
