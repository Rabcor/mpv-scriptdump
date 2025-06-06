-- Does not work with losslessly concatenated files (h264/hevc in mp4 at least)
-- If on hwdec use copyback for optimal results (hwdec=auto-copy)
-- TODO: Find a way to detect concatenated files and disable functionalityo n those files.

local options = {
	autoloop_duration = 60,		-- Seconds (1 min)
	seamlessloop = true,		-- Enable filter based seamless looping
	allowsoftseamless = true,	-- Even when seamless looping is disabled, try to make looping seamless with a softer approach when applicable
	allowseek = true			-- Allow seeking (seeking breaks seamless looping).
	}
	
mp.options = require "mp.options"
mp.options.read_options(options)
local maxaudio = 2.14748e+09
local maxframes = 32767
local duration = 0
local frames = 0
local cpuaccess = false
local looping = nil
local time = 0.0
local lasttime = 0.0
local seamlessmode = false
local seekbuffer = 0.05 -- Expected delay between executions
local allowreset = true

function disableseamless()
	local filters = mp.get_property("vf") .. mp.get_property("af") 
	if string.match(filters,"seamlessloop") then
		mp.command("no-osd vf remove @seamlessloop")
    	mp.command("no-osd af remove @seamlessloop")
    end
  if string.match(mp.get_property("lavfi-complex"), "loop") then
  	mp.set_property("lavfi-complex", "[vid1]null[vo]")
  end
end

function softseamless()
	if not options.allowsoftseamless then
		return
	end
	if cpuaccess then
		mp.command("no-osd vf set @seamlessloop:loop=-1")
		--mp.command("no-osd af set @seamlessloop:aloop=-1")
	else			
		mp.set_property("lavfi-complex", "[vid1]loop=-1[vo]")
		--mp.command("no-osd af set @seamlessloop:aloop=-1")
	end
	seamlessmode = false
end

function update()
	local hwdec = mp.get_property("hwdec-current")
	if hwdec ~= nil then
		if string.match(hwdec, "copy") or hwdec == "no" then
			cpuaccess = true
		else
			cpuaccess = false
		end
	else
		hwdec = mp.get_property("hwdec")
		if string.match(hwdec, "copy") or hwdec == "no" then
			cpuaccess = true
		else
			cpuaccess = false
		end
	end
	looping = mp.get_property_native("loop-file")
	duration = mp.get_property_native("duration")
	if mp.get_property("container-fps") ~= nil then
    	frames = math.ceil(mp.get_property("container-fps") * duration) -- Not sure if this really matters
	else
		frames = maxframes
	end
	time = mp.get_property_native("time-pos")
	seamlessmode = string.match(mp.get_property("vf"), '@seamlessloop.loop.-1.size')
	if not seamlessmode then
		seamlessmode = string.match(mp.get_property("lavfi-complex"), "loop.-1.size")
	end
	if time == nil then
		time = 0.000
	end
end

function seamlessloop(loop_property, status)
	update()
	looping = status
	if not looping then
		disableseamless()
    	return
	elseif not options.seamlessloop then
		return
	elseif frames > maxframes then
		return
	elseif seamlessmode then
		return
	end
	if looping and frames <= maxframes then
		if allowreset then
			allowreet = false
			mp.command("no-osd seek 0 absolute")
		end
		if cpuaccess then
			mp.command("no-osd vf set @seamlessloop:loop=-1:size=" .. frames)
			mp.command("no-osd af set @seamlessloop:aloop=-1:size=" .. maxaudio)
		else
			mp.set_property("lavfi-complex", string.format("[vid1]loop=-1:size=%d[vo]", frames))
			mp.command("no-osd af set @seamlessloop:aloop=-1:size=" .. maxaudio)
		end
	end
end

function autoloop()
	if options.autoloop_duration == 0 then
		return
	end
	
    -- Cancel operation if there is no file duration
    if not duration then
    	mp.set_property_native("loop-file", false)
        return
    end
    -- Loops file if was_loop is false, and file meets requirements
    if not looping and duration <= options.autoloop_duration then
        mp.set_property_native("loop-file", true)
        mp.set_property_bool("file-local-options/save-position-on-quit", false)
		if not options.seamlessloop then -- try to mitigate pause at end of loops, doesn't always work.
			mp.command("no-osd seek 0 absolute")
			softseamless()
		end
    elseif looping and duration > options.autoloop_duration then
        mp.set_property_native("loop-file", false)
    elseif looping then
    	if not options.seamlessloop then -- try to mitigate pause at end of loops, doesn't always work.
			mp.command("no-osd seek 0 absolute")
			softseamless()
		end
    end
end

function initialize()
	disableseamless()
	update()
	if duration <= options.autoloop_duration then
		mp.command("no-osd seek 0 absolute")
	end
	autoloop(looping)
	-- This is how we hijack the loop function in mpv and toggle seamless looping in tandem with it.
	mp.observe_property("loop-file", "native", seamlessloop)
	mp.observe_property("loop", "native", seamlessloop)
end

mp.register_event("file-loaded", initialize)

mp.register_event("playback-restart", function() 
	update()
	if math.abs(time - lasttime) < seekbuffer or not looping then
		return
	elseif options.seamlessloop then
		if not options.allowseek then
			disableseamless()
			allowreset = true
			seamlessloop("loop-file", looping)
		elseif time < seekbuffer * 2 then
			allowreset = true
			seamlessloop("loop-file", looping)
		else
			disableseamless()
			softseamless()
		end
	end
	update()
	lasttime = time
end)
