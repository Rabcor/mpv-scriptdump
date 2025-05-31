-- For optimal results, set hwdec=auto-copy

-- TODO: Make it possible to save non-h264/h265 videos (requires encoding them)
-- TODO: Convert SAVE bool to a keybind

EDGEBUFFER = 5 -- how many pixels from edge before snapping to edge.

CORNER="top-left" -- I laid some groundwork to make it possible to change this but it's incomplete.

SAVE=true -- SHould be replaced with keybind to save?

COLORSTRING="color=red@0.5:thickness=1:"

-- Below are global variables that are set within the code, don't change them.
CROPPING = false
SOURCE = { 1, 1 }
VIDEO = { 1, 1 }
COPYBACK = false

-- Set mouse x and y coords as global variables so that they are never nil, it's ugly but i suck with lua
x = 0
y = 0

local function print(s)
	mp.msg.info(s)
	mp.osd_message(s,3)
end

local function getres()
	if mp.get_property_native"dwidth" ~= nil and mp.get_property("video-target-params/dw") ~= nil then
		SOURCE = { x = mp.get_property_native"dwidth", y = mp.get_property_native"dheight" } -- Not sure why this needs to be re-fetched all the time
		VIDEO = { x = mp.get_property("video-target-params/dw"), y = mp.get_property("video-target-params/dh") }
	end
	local hwdec = mp.get_property("hwdec-current")
	if hwdec ~= nil then
		if string.match(hwdec, "copy") then
			COPYBACK = true
		else
			COPYBACK = false
		end
	else
		COPYBACK = false
	end	
end

local function getcorner(c) -- c is CORNER, s is source resolution
	local corner = { x = 0, y = 0 }
	if c == "top-right" then
		corner.x = SOURCE.x
		corner.y = 0
	elseif c == "bottom-left" then
		corner.x = 0
		corner.y = SOURCE.y
	elseif c == "bottom-right" then
		corner.x = SOURCE.x
		corner.y = SOURCE.y
	end
	return corner
end

local function cyclecorner()
	if CORNER == "top-left" then
		CORNER="top-right" 
	elseif CORNER == "top-right" then
		CORNER="bottom-left" 
	elseif CORNER == "bottom-left" then
		CORNER="bottom-right" 
	else
		CORNER="top-left"
	end
	print("Cropping from " .. CORNER .. " corner.")
end

-- Translate crop coordinates to h264/h265 metadata for ffmpeg.
local function mdcrop(mousex, mousey)
	local outx = math.floor(SOURCE.x - mousex) 
	local outy = math.floor(SOURCE.y - mousey)
	if not ( outx % 2 == 0 ) then
		outx = outx - 1
	end
	if not ( outy % 2 == 0 ) then
		outy = outy - 1
	end
	local metacrop="crop_right=" .. outx .. ":crop_bottom=" .. outy
	if CORNER == "top-right" then
		metacrop="crop_left=" .. outx .. ":crop_bottom=" .. outy
	elseif CORNER == "bottom-left" then
		metacrop="crop_right=" .. outx .. ":crop_top=" .. outy
	elseif CORNER == "bottom-right" then
		metacrop="crop_left=" .. outx .. ":crop_top=" .. outy
	end
	local codec = mp.get_property("video-codec")
	if string.match(codec, "H.264") then
		return metacrop:gsub("^c", "h264_metadata=c") -- had to use substitution instead of concatenation because otherwise it mysteriously fails.
	elseif string.match(codec, "H.265") then
		return metacrop:gsub("^c", "hevc_metadata=c")
	end
	return false
end

local function save(mousex, mousey, cornerx, cornery)
	local mx, my = math.abs(cornerx - mousex), math.abs(cornery - mousey) -- Prepare coordinates for ffmpeg
	local codec = mp.get_property("video-codec")
	if SAVE and string.match(codec, "H.26") then
		local file = mp.get_property("path")
		local filename = mp.get_property("filename/no-ext")
		local extension = mp.get_property("filename"):match("^.+(%..+)$")
		local outdir = file:match("(.*[/\\\\])")
		local outfile = filename .. "_Cropped" .. extension
		local metadatacrop = {
			"ffmpeg",
			"-nostdin", "-y",
			"-loglevel", "error",
			"-i", file,
			"-c", "copy",
			"-bsf:v", mdcrop(mx, my),
			outdir .. outfile
		}
		mp.command_native_async({
			name = "subprocess",
			args = metadatacrop,
			playback_only = false,
		},function() print("Crop saved to: " .. 
		outdir .. outfile ) end)
	end
end


local function preview(name, value)
	getres() -- has to be called every time, not sure why since the variables are global, but without this it will always crash on the line where I set diff.
	local osd = { x = mp.get_property_native"osd-width", y = mp.get_property_native"osd-height" }
	local diff = { x = SOURCE.x / VIDEO.x, y = SOURCE.y / VIDEO.y }
	local corner = getcorner(CORNER, source)
	local drawbox = ""
	if not CROPPING then -- This is where mpv cropping gets done.
		mp.command("no-osd vf remove @croppw")
		if CORNER == "top-left" then
			mp.set_property('video-crop', string.format("%dx%d+%d+%d", x, y, 0, 0))
		elseif CORNER == "top-right" then
			mp.set_property('video-crop', string.format("%dx%d+%d+%d", corner.x - x, y, x, 0))
		elseif CORNER == "bottom-left" then
			mp.set_property('video-crop', string.format("%dx%d+%d+%d", x, corner.y - y, 0, y))
		elseif CORNER == "bottom-right" then
			mp.set_property('video-crop', string.format("%dx%d+%d+%d", 0, 0, x, y))
		end
		if not COPYBACK then
			if CORNER == "bottom-right" then
			mp.set_property("lavfi-complex", string.format("[vid1]crop=%d:%d:%d:%d[vo]", corner.x, corner.y, math.abs(corner.x - x), math.abs(corner.y - y)))
			else
			mp.set_property("lavfi-complex", string.format("[vid1]crop=%d:%d:%d:%d[vo]", math.abs(corner.x - x), math.abs(corner.y - y), corner.x, corner.y))
			end
		end
		save(x,y,corner.x, corner.y)
	end
	if value ~= nil then
		x, y = value.x, value.y
	else -- Do not go beyond this point if mouse position isn't valid. Prevents some crashes.
		return 
	end
	if VIDEO.x ~= osd.x then
		x = (x - ((osd.x - VIDEO.x) * 0.5)) * diff.x
	else
		x = x * diff.x
		--x = math.abs(corner.x - (x * diff.x))
	end
	if VIDEO.y ~= osd.y then
		y = (y - ((osd.y - VIDEO.y) * 0.5)) * diff.y
	else
		y = y * diff.y
		--y = math.abs((y * diff.y) - corner.y)
	end
	if x > SOURCE.x - EDGEBUFFER then
		x = SOURCE.x
	end
	if y > SOURCE.y - EDGEBUFFER then
		y = SOURCE.y
	end
	if COPYBACK then
		if CORNER == "top-right" then
			mp.command("no-osd vf set @croppw:" .. string.format("drawbox=%sw=%d:h=%d:x=%d:y=%d",COLORSTRING, 0,y,x,0) )
		elseif CORNER == "bottom-left" then
			mp.command("no-osd vf set @croppw:" .. string.format("drawbox=%sw=%d:h=%d:x=%d:y=%d",COLORSTRING, x,0,0,y) )
		elseif CORNER == "bottom-right" then
			mp.command("no-osd vf set @croppw:" .. string.format("drawbox=%sw=%d:h=%d:x=%d:y=%d",COLORSTRING, 0,0,x,y) )
		else
			mp.command("no-osd vf set @croppw:" .. string.format("drawbox=%s:w=%d:h=%d:x=%d:y=%d",COLORSTRING, x,y,0,0) )
		end
	else
		if CORNER == "top-right" then
			drawbox = string.format("[vid1]drawbox=%sw=%d:h=%d:x=%d:y=%d[vo]",COLORSTRING, 0,y,x,0)
		elseif CORNER == "bottom-left" then
			drawbox = string.format("[vid1]drawbox=%sw=%d:h=%d:x=%d:y=%d[vo]",COLORSTRING, x,0,0,y)
		elseif CORNER == "bottom-right" then
			drawbox = string.format("[vid1]drawbox=%sw=%d:h=%d:x=%d:y=%d[vo]",COLORSTRING, 0,0,x,y)
		else
			drawbox = string.format("[vid1]drawbox=%sw=%d:h=%d:x=%d:y=%d[vo]",COLORSTRING, x,y,0,0)
		end
		mp.set_property("lavfi-complex", drawbox)
	end
end

local function crop()
	mp.set_property('video-crop', '')
	if CROPPING then -- crop
		CROPPING = false
		mp.unobserve_property(preview)
		preview() -- We need some values that the preview function gets to crop, so I reuse it for that.
	else -- Start previewing
		CROPPING = true
		mp.set_property_bool("pause", true)
		mp.observe_property("mouse-pos", "native", preview)
	end
end

local function cancel_crop()
	if CROPPING then
		print("Crop cancelled")
	end
	mp.set_property('video-crop', '')
	mp.unobserve_property(preview)
	getres()
	if string.match(mp.get_property("lavfi-complex"), "crop") or string.match(mp.get_property("lavfi-complex"), "drawbox") then
		mp.set_property("lavfi-complex", "[vid1] drawbox [vo]") -- couldn't find a way to safely clear this completely.		
	else
		mp.command("no-osd vf remove @croppw")
	end
	CROPPING = false
end

mp.add_key_binding(nil,"cycle_crop_corner", cyclecorner)
mp.add_key_binding(nil, "crop", crop)
mp.add_key_binding(nil, "cancel_crop", cancel_crop)
mp.add_key_binding(nil, "save", save)

--mp.register_event('file-loaded', initialize)
mp.msg.info("VIDEO-CROPPER LOADED")
