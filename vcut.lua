-- Set true to save to an mp4 container, only way for precise cutting that's actually lossless. May cause A/V desync for some players, including web players.
PRECISE = true 

START_TIME = nil

local function print(s)
	mp.msg.info(s)
	mp.osd_message(s,3)
end

-- Generate the timestamp string placed in the output filename, yes this needed to be half the code lol.
local function generate_timestring(ts_start, ts_stop)
	local separator = "-"
	local seconds_start = math.ceil(ts_start)
	local seconds_stop = math.floor(ts_stop)
	local timestring = string.format("%02d",seconds_start)
	if seconds_start > 60 then
		local minutes_start = math.floor(seconds_start / 60)
		minutes_start = math.floor(seconds_start / 60)
		seconds_start = seconds_start % 60
		timestring = string.format("%02d",minutes_start) .. separator .. string.format("%02d",seconds_start)
		if minutes_start > 60 then
			local hours_start = math.floor(minutes_start / 60)
			minutes_start = minutes_start % 60
			timestring = string.format("%02d",hours_start) .. separator .. string.format("%02d",minutes_start) .. separator .. string.format("%02d",seconds_start)
		end
	end
	if seconds_stop > 60 then
		local minutes_stop = math.floor(seconds_stop / 60)
		seconds_stop = seconds_stop % 60
		timestring = timestring .. "_To_" .. string.format("%02d",minutes_stop) .. separator .. string.format("%02d",seconds_stop)
		if minutes_stop > 60 then
			local hours_stop = math.floor(minutes_stop / 60)
			minutes_stop = minutes_stop % 60
			timestring = timestring .. "_To_" .. string.format("%02d",hours_stop) .. separator .. string.format("%02d",minutes_stop) .. separator .. string.format("%02d",seconds_stop)
		end
	else
		timestring = timestring .. "_To_" .. string.format("%02d",seconds_stop)
	end
	return timestring
end

function file_exists(name)
   local f = io.open(name, "r")
   return f ~= nil
end

local function cut(ts_start,ts_stop)
	local timestring = generate_timestring(ts_start, ts_stop)
	local file = mp.get_property_native("path")
	local filename = mp.get_property_native("filename/no-ext")
	local extension = mp.get_property_native("filename"):match("^.+(%..+)$") -- No longer needed, we now convert to mp4 because it supports setting a starting timestamp without encoding.
	local subcodec = "copy"
	local outdir = file:match("(.*[/\\\\])")
	local outfile = filename .. "-From_" .. timestring
	local cutcmd = {}
	local message = ""
	local one_frame = 0,0458333333333 
	if mp.get_property_native("container-fps") ~= nil then
		one_frame = 1.1 / mp.get_property_native("container-fps")
	end
	if PRECISE then
		extension = ".mp4"
		subcodec = "mov_text"
		webformat = "--merge-output-format mp4"
	end
	if io.open(file, "r") ~= nil then
		outfile = outfile .. extension
		print("Cutting...")
		cutcmd = {
			"ffmpeg",
			"-nostdin", "-y",
			"-loglevel", "error",
			"-ss", tostring(ts_start),
			"-to", tostring(ts_stop - one_frame), -- Because there's often an extra frame, we remove the last frame from the cut.
			"-i", file,
			"-c:a", "copy",
			"-c:v", "copy",
			"-c:s", subcodec,
			"-movflags", "+faststart",
			outdir .. outfile
		}
		message = "Cut: " .. string.format("%.2f",ts_stop - ts_start) .. " Seconds\nSaved to:" .. outdir .. outfile
	else
		print("Downloading...")
		cutcmd = {
			"yt-dlp", "--force-overwrites",
			"-f", "bestvideo*+bestaudio/best",
			"--download-sections", "*" .. tostring(ts_start) .. "-" .. tostring(ts_stop),
			"-S", "proto:https", -- Not using this can cause issues.
			file
		}
		if PRECISE then
			cutcmd[#cutcmd+1]="--merge-output-format"
			cutcmd[#cutcmd+1]="mp4"
		end
		message = "Cut: " .. string.format("%.2f",ts_stop - ts_start) .. " Seconds\nSaved to:" .. mp.get_property("working-directory")
	end
	mp.command_native_async({
		name = "subprocess",
		args = cutcmd ,
		playback_only = false,
	}, function() print(message) end)
end

local function place_timestamp()
	local time = mp.get_property_number("time-pos")
	if not START_TIME then
		print("Cut timestamp placed: " .. string.format("%.2f",time))
		START_TIME = time
		return
	end
	if time > START_TIME then
		cut(START_TIME, time)
		START_TIME = nil
	else
		print("Invalid cut")
		START_TIME = nil
	end
end

local function cancel_cut()
	if START_TIME then
		START_TIME = nil
		print("Cut cancelled")
	end
end

mp.add_key_binding(nil, "cut", place_timestamp)
mp.add_key_binding(nil, "cancel_cut", cancel_cut)

mp.msg.info("VIDEO-CUTTER LOADED")
