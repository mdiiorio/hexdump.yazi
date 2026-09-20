--- Minimal stand-ins for the parts of the Yazi runtime that main.lua touches,
--- so the previewer can be exercised with a plain `lua` interpreter.
---
--- The fakes are deliberately unhelpful where the real API is: `Fd:read()`
--- returns short reads, because the real one is a single syscall and the
--- refill loops in main.lua exist to cope with that.

local H = {}

local function Style()
	local o = {}
	function o:fg(c)
		o.color = c
		return o
	end
	return o
end

local function Span(s)
	local o = { text = s }
	function o:style(st)
		o.style_ref, o.color = st, st and st.color
		return o
	end
	return o
end

local function Line(spans)
	local o = { spans = spans }
	function o:area() return o end
	function o:reverse() return o end
	return o
end

local function Text(lines)
	local o = { lines = lines }
	function o:area() return o end
	function o:wrap() return o end
	return o
end

--- Installs the globals main.lua expects. `opts.th` becomes the `th` global,
--- so a test can supply a `[hexdump]` theme section or leave it absent.
--- @return table sink capturing what the previewer did
function H.stub(opts)
	local sink = { emitted = nil, msg = nil, text = nil }

	ui = { Style = Style, Span = Span, Line = Line, Text = Text, Wrap = { YES = 1, NO = 0 } }
	th = opts and opts.th or nil

	ya = {
		preview_widget = function(_, widget) sink.text = widget end,
		emit = function(action, args) sink.emitted = { action = action, args = args } end,
		drop = function() end,
		err = function() end,
		dbg = function() end,
	}

	fs = {
		access = function()
			local a = {}
			function a:read() return a end
			function a:open(url)
				local f = io.open(url, "rb")
				if not f then
					return nil, "ENOENT"
				end
				local fd = {}
				function fd:read(n) return f:read(math.min(n, 7)) or "" end
				return fd
			end
			return a
		end,
	}

	local real = require
	_G.require = function(name)
		if name == "empty" then
			return { msg = function(_, s) sink.msg = s end }
		elseif name == "code" then
			return { seek = function() end }
		end
		return real(name)
	end

	return sink
end

--- Writes `bytes` to a temp file and returns its path, registering it for
--- cleanup by `H.cleanup()`.
local tmps = {}
function H.fixture(bytes)
	local path = os.tmpname()
	local f = assert(io.open(path, "wb"))
	f:write(bytes)
	f:close()
	tmps[#tmps + 1] = path
	return path
end

function H.cleanup()
	for _, p in ipairs(tmps) do
		os.remove(p)
	end
	tmps = {}
end

--- Calls `peek` once against a fixture.
--- @param job table `path`, and optionally `skip`, `w`, `h`, `columns`, `group`
--- @return table sink, with `lines` added: the rendered rows as plain strings
function H.peek(M, sink, job)
	local f = assert(io.open(job.path, "rb"))
	local size = f:seek("end")
	f:close()

	M:peek {
		area = { w = job.w or 80, h = job.h or 8 },
		file = { url = job.path, cha = { len = size } },
		skip = job.skip or 0,
		args = { columns = job.columns, group = job.group },
	}

	if sink.text then
		sink.lines = {}
		for _, line in ipairs(sink.text.lines) do
			local parts = {}
			for _, span in ipairs(line.spans) do
				parts[#parts + 1] = span.text
			end
			sink.lines[#sink.lines + 1] = table.concat(parts)
		end
	end
	return sink
end

--- Colour of the first span whose text contains `needle`.
function H.colour_of(sink, needle)
	for _, line in ipairs(sink.text.lines) do
		for _, span in ipairs(line.spans) do
			if span.text:find(needle, 1, true) then
				return span.color
			end
		end
	end
end

return H
