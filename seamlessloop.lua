local options = {
	autoloop_duration = 60,		-- Seconds (1 min) set to 0 to disable
	seamlessloop = true,		-- Enable filter based seamless looping
	allowseek = true		-- Allow seeking (seeking breaks seamless looping).
	}
	
mp.options = require "mp.options"
mp.options.read_options(options)
local maxaudio = 2.14748e+09

function seamlessloop(loop_property, looping)
	if not looping then
		mp.command("no-osd vf remove @seamlessloop")
    	mp.command("no-osd af remove @seamlessloop")
    	return
	elseif not options.seamlessloop then
		return
	end
	local duration = mp.get_property_native("duration")
	local frames = 32767
	if mp.get_property("container-fps") ~= nil then
    	frames = math.ceil(mp.get_property("container-fps") * duration)
    end
	if looping and frames < 32767 then
		mp.command("no-osd seek 0 absolute")
		mp.command("no-osd vf set @seamlessloop:loop=-1:size=" .. frames)
		mp.command("no-osd af set @seamlessloop:aloop=-1:size=" .. maxaudio) 
	elseif frames > 32767 then
		mp.osd_message("File is too long for seamless looping, falling back to normal looping")
	end
end

function autoloop(looping)
	if options.autoloop_duration == 0 then
		return
	end
	local duration = mp.get_property_native("duration")
	local frames = mp.get_property("container-fps") * duration
	if not options.seamlessloop then -- try to make the normal looping seamless, helps a lot but doesn't always work.
		mp.command("no-osd vf set @seamlessloop:loop=-1")
		mp.command("no-osd af set @seamlessloop:aloop=-1:size=" .. maxaudio)
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
        -- Unloops file if was_loop is true, and file does not meet requirements
    elseif looping and duration > options.autoloop_duration then
        mp.set_property_native("loop-file", false)
    end
end

-- Disable loop filter on seek. Restore it when starting over. Called on playback-restart.
function recover()
		local looping = mp.get_property_native("loop-file")
		local time = tonumber(mp.get_property("time-pos")) 
		local seamlessmode = string.match(mp.get_property("vf"), '@seamlessloop.loop.-1.size')
		if time == 0.0 and looping then
			if not seamlessmode  and options.seamlessloop then
				seamlessloop("loop-file", looping)
			end
		elseif time > 0.1 and looping then	-- Disable on seek. We could instead seek to start, set loop=-1 (no size) then seek back to the desired time, however it only savees u like 1/10 times so not worth the hassle.
			mp.command("no-osd vf remove @seamlessloop")
    		mp.command("no-osd af remove @seamlessloop")
		end
		if time > 0.1 and not options.allowseek then
			seamlessloop("loop-file", looping)
		end
end

function initialize()
	autoloop(mp.get_property_native("loop-file"))
	-- This is how we hijack the loop function in mpv and toggle seamless looping in tandem with it.
	mp.observe_property("loop-file", "native", seamlessloop)
	mp.observe_property("loop", "native", seamlessloop)
end

mp.register_event("file-loaded", initialize)

mp.register_event("playback-restart", recover)
