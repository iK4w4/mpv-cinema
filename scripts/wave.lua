-- wave.lua
-- Copyright (c) 2026 iK4w4 — MIT License (see LICENSE at the repo root).
--
-- Speech waveform track for mpv + uosc.
--
-- Builds a whole-file waveform on file load and draws it as a
-- track above the uosc controls, on the same time axis as the
-- timeline. Cyan = speech, grey = silence. No key press and no
-- menu entry are needed: open a file and the track appears.
--
-- Layout (uosc 5.13, values from script-opts/uosc.conf):
--   window_border=1, timeline_size=36, timeline_border=1,
--   controls_size=32, controls_margin=8, scale_fullscreen=1.2
--   timeline_top = H - 1 - 36*scale - 1*scale
--   controls_top = timeline_top - 8*scale - 32*scale
-- The track sits above the controls (bottom = controls_top).
-- It stays visible when uosc fades, so speech stays readable.
--
-- Renderer: BGRA bitmap via overlay-add (id 43; thumbfast uses
-- 42). No ASS overlay, no video filter: video-filter coordinates
-- are video-frame coordinates and cannot align with the OSD
-- timeline under letterboxing.
--
-- Peaks are decoded once per file (ffmpeg if available, otherwise
-- mpv itself), cached under cache/waveforms/, and normalised by
-- the 95th percentile of the non-zero bars, so a single loud
-- spike does not push all speech below the threshold.
-- Local files only; streams are refused.
--
-- Keys (see input.conf): w/W hide/show, Alt+RIGHT/LEFT jump to
-- the next / previous speech segment.

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    height = 48,
    speech_threshold = 0.12,
    min_run_bars = 2,
    sample_rate = 8000,
}
options.read_options(opts, "wave")
-- Clamp options to sane ranges.
if opts.height < 16 then opts.height = 16 end
if opts.height > 128 then opts.height = 128 end
if opts.speech_threshold < 0.01 then opts.speech_threshold = 0.01 end
if opts.speech_threshold > 0.9 then opts.speech_threshold = 0.9 end
if opts.sample_rate < 4000 then opts.sample_rate = 4000 end
if opts.sample_rate > 16000 then opts.sample_rate = 16000 end

local OVERLAY_ID = 43
local WINDOW_BORDER = 1
local TIMELINE_SIZE = 36
local TIMELINE_BORDER = 1
local CONTROLS_SIZE = 32
local CONTROLS_MARGIN = 8
local SCALE_FULLSCREEN = 1.2 -- must match uosc.conf scale_fullscreen

local state = {
    visible = false,
    peaks = nil,
    segments = nil,
    path = nil,
    duration = nil,
    aid = nil,
    bgra_file = nil,
    shown_loaded_once = false,
    building = false,
    pending_toggle = false,
    user_hidden = false,
    load_timer = nil,
    redraw_timer = nil,
    last_draw_key = nil,
    last_bgra = nil,
    cache_ok = false,
}

local function osd(msg, dur)
    mp.osd_message(msg, dur or 5)
end

local function script_dir()
    return mp.get_script_directory()
end

local function cache_dir()
    return utils.join_path(script_dir(), "../cache/waveforms")
end

local function ensure_dir_once(path)
    local is_windows = package.config:sub(1, 1) == "\\"
    if is_windows then
        path = path:gsub("/", "\\")
        os.execute('mkdir "' .. path .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
    -- verify it exists / is writable, once, at load
    local test = io.open(utils.join_path(path, ".write-test"), "w")
    if test then test:close() os.remove(utils.join_path(path, ".write-test")) state.cache_ok = true
    else state.cache_ok = false end
end
ensure_dir_once(cache_dir())

local function write_error(msg)
    local f = io.open(utils.join_path(cache_dir(), "last-error.txt"), "w")
    if f then f:write(msg) f:close() end
end

local function current_aid()
    return mp.get_property_native("aid")
end

local function hash_path(path, size, duration, aid)
    local h = 5381
    local s = path .. "|" .. tostring(size or 0) .. "|" .. string.format("%.3f", duration or 0) .. "|" .. tostring(aid or 0)
    for i = 1, #s do
        h = ((h * 33) + string.byte(s, i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function find_exe(basename)
    local dir = script_dir()
    local is_windows = package.config:sub(1, 1) == "\\"
    local ext = ""
    if is_windows then ext = ".exe" end
    local candidates = {}
    -- ffmpeg lives next to mpv.exe (../../ from scripts/), never in
    -- portable_config/ itself. The old ../ candidate was wrong.
    candidates[#candidates + 1] = utils.join_path(dir, "../../" .. basename .. ext)
    if is_windows and basename == "ffmpeg" then
        candidates[#candidates + 1] = "C:\\ffmpeg\\bin\\ffmpeg.exe"
    end
    for _, c in ipairs(candidates) do
        local f = io.open(c, "rb")
        if f then f:close() return c end
    end
    return basename .. ext
end

local function compute_segments(peaks, duration, threshold, min_run)
    local segments = {}
    local n = #peaks
    if n == 0 or not duration or duration <= 0 then return segments end
    local sec_per_bar = duration / n
    local in_speech = false
    local run_start = 0
    local run_len = 0
    local function flush(end_bar)
        if run_len >= min_run then
            segments[#segments + 1] = {
                start = (run_start - 1) * sec_per_bar,
                ["end"] = end_bar * sec_per_bar,
            }
        end
    end
    for i = 1, n do
        local is_speech = peaks[i] >= threshold
        if is_speech and not in_speech then
            in_speech = true
            run_start = i
            run_len = 1
        elseif is_speech and in_speech then
            run_len = run_len + 1
        elseif not is_speech and in_speech then
            flush(i - 1)
            in_speech = false
            run_len = 0
        end
    end
    if in_speech then flush(n) end
    return segments
end

local function bar_count_for(duration)
    return math.max(100, math.floor(duration / 0.15))
end

local function peaks_from_raw(data, duration)
    local total_samples = math.floor(#data / 2)
    if total_samples == 0 then return nil end
    local bar_count = bar_count_for(duration)
    local samples_per_bar = math.max(1, math.floor(total_samples / bar_count))
    local peaks = {}
    for b = 1, bar_count do
        local maxv = 0
        local start_s = (b - 1) * samples_per_bar
        for s = 0, samples_per_bar - 1, 4 do
            local idx = (start_s + s) * 2 + 1
            if idx + 1 > #data then break end
            local lo = string.byte(data, idx)
            local hi = string.byte(data, idx + 1)
            local v = lo + hi * 256
            if v >= 32768 then v = v - 65536 end
            if v < 0 then v = -v end
            if v > maxv then maxv = v end
        end
        peaks[b] = maxv
    end
    -- Normalise by the 95th percentile of the non-zero bars,
    -- not by the global maximum. A single full-scale spike is
    -- one bar out of many non-zero bars; the 95th percentile of
    -- that set is the speech level, the spike is ignored.
    local nz = {}
    for _, p in ipairs(peaks) do if p > 0 then nz[#nz + 1] = p end end
    if #nz == 0 then return nil end
    table.sort(nz)
    local denom = nz[math.max(1, math.floor(0.95 * #nz))]
    if denom <= 0 then return nil end
    for i = 1, #peaks do
        peaks[i] = math.min(peaks[i] / denom, 1.0)
    end
    return peaks
end

local function decode_with_ffmpeg(path, raw_file)
    local ffmpeg = find_exe("ffmpeg")
    local res = utils.subprocess({
        args = {
            ffmpeg, "-v", "error", "-y",
            "-i", path,
            "-vn", "-ac", "1", "-ar", tostring(opts.sample_rate),
            "-f", "s16le", "-acodec", "pcm_s16le",
            raw_file,
        },
        cancellable = true,
    })
    if res.status == 0 then return true, "ffmpeg" end
    return false, string.format("ffmpeg %s status %s error %s stderr %s",
        tostring(ffmpeg), tostring(res.status), tostring(res.error), tostring(res.stderr))
end

local function decode_with_mpv(path, raw_file)
    local mpv = find_exe("mpv")
    local res = utils.subprocess({
        args = {
            mpv, "--no-config", "--load-scripts=no",
            "--no-video", "--no-sub", "--no-osc", "--really-quiet",
            "--o=" .. raw_file, "--of=rawaudio", "--oac=pcm_s16le",
            "--ovc=no", "--audio-channels=1",
            "--audio-samplerate=" .. tostring(opts.sample_rate),
            path,
        },
        cancellable = true,
    })
    if res.status == 0 then return true, "mpv" end
    return false, string.format("mpv %s status %s error %s stderr %s",
        tostring(mpv), tostring(res.status), tostring(res.error), tostring(res.stderr))
end

local function try_load_cache(path, duration, file_size, aid)
    if not state.cache_ok then
        osd("Wave timeline: cache dir not writable, see cache/waveforms/last-error.txt", 5)
        write_error("cache dir not writable: " .. cache_dir() .. "\n")
        return false
    end
    local key = hash_path(path, file_size, duration, aid)
    local cf = io.open(utils.join_path(cache_dir(), key .. ".txt"), "r")
    if not cf then return false end
    local content = cf:read("*a")
    cf:close()
    -- Cache format: first line "v1 <bar_count>", then peaks.
    local header_count = content:match("^v1%s+(%d+)")
    if not header_count then return false end
    local expected = bar_count_for(duration)
    if tonumber(header_count) ~= expected then return false end
    local peaks = {}
    local body = content:match("\n(.*)$") or ""
    for num in body:gmatch("([0-9]+%.?[0-9]*)") do
        peaks[#peaks + 1] = tonumber(num) or 0
    end
    if #peaks ~= expected then return false end
    local max_peak = 0
    for _, p in ipairs(peaks) do if p > max_peak then max_peak = p end end
    if max_peak <= 0 then return false end
    state.peaks = peaks
    state.segments = compute_segments(peaks, duration, opts.speech_threshold, opts.min_run_bars)
    state.path = path
    state.duration = duration
    state.aid = aid
    state.decoder_used = "cache"
    return true
end

local function load_or_build()
    local path = mp.get_property("path")
    if not path then
        osd("Wave timeline: no file loaded", 5)
        write_error("load_or_build: no path\n")
        return false
    end
    if path:match("^https?://") or path:match("^ftp://") then
        osd("Wave timeline: local files only", 5)
        return false
    end
    local duration = mp.get_property_native("duration")
    local file_size = mp.get_property_native("file-size")
    local aid = current_aid()
    if not duration or duration <= 0 then
        -- duration not known yet; caller retries once it is observed.
        return false
    end
    if state.path == path and state.peaks and state.aid == aid then return true end
    if try_load_cache(path, duration, file_size, aid) then return true end
    local key = hash_path(path, file_size, duration, aid)
    local cache_file = utils.join_path(cache_dir(), key .. ".txt")
    osd("Wave timeline: building... (first time only)", 8)
    local raw_file = utils.join_path(cache_dir(), key .. ".raw")
    local ok, used, err1 = decode_with_ffmpeg(path, raw_file)
    local err2 = ""
    if not ok then
        ok, used, err2 = decode_with_mpv(path, raw_file)
    end
    if not ok then
        write_error("ffmpeg: " .. tostring(err1) .. "\nmpv: " .. tostring(err2) .. "\nfile: " .. tostring(path) .. "\n")
        osd("Wave timeline: no decoder - run get-ffmpeg.bat, see cache/waveforms/last-error.txt", 8)
        return false
    end
    local rf = io.open(raw_file, "rb")
    if not rf then
        write_error("could not open decoded raw file: " .. raw_file .. "\n")
        osd("Wave timeline: decode produced no audio file, see last-error.txt", 8)
        return false
    end
    local data = rf:read("*a")
    rf:close()
    os.remove(raw_file)
    -- Truncated-decode check. Expected bytes = duration * sr * 2.
    local expected_bytes = duration * opts.sample_rate * 2
    if #data < expected_bytes * 0.95 or #data > expected_bytes * 1.05 then
        write_error(string.format("truncated decode: got %d bytes, expected %.0f (duration %.3f, sr %d)\nfile: %s\n",
            #data, expected_bytes, duration, opts.sample_rate, tostring(path)))
        osd("Wave timeline: decode was truncated, see cache/waveforms/last-error.txt", 8)
        return false
    end
    local peaks = peaks_from_raw(data, duration)
    if not peaks then
        osd("Wave timeline: audio is silent or has no audio", 8)
        return false
    end
    -- atomic cache write: temp file, then rename.
    local tmp_file = cache_file .. ".tmp"
    local out = io.open(tmp_file, "w")
    if not out then
        write_error("could not write cache file: " .. tmp_file .. "\n")
        osd("Wave timeline: could not save cache, see last-error.txt", 8)
    else
        local parts = {}
        for i = 1, #peaks do parts[i] = string.format("%.3f", peaks[i]) end
        out:write("v1 " .. tostring(#peaks) .. "\n" .. table.concat(parts, ","))
        out:close()
        os.rename(tmp_file, cache_file)
    end
    state.peaks = peaks
    state.segments = compute_segments(peaks, duration, opts.speech_threshold, opts.min_run_bars)
    state.path = path
    state.duration = duration
    state.aid = aid
    state.decoder_used = used
    return true
end

-- Geometry, from uosc 5.13.0 source (see header). scale is 1.0 windowed,
-- SCALE_FULLSCREEN when fullscreen/maximised. Returns x, w, top, h.
local function wave_geometry(osd_w, osd_h)
    local fullscreen = mp.get_property_native("fullscreen")
    local scale = fullscreen and SCALE_FULLSCREEN or 1.0
    local strip_x = math.floor(WINDOW_BORDER * scale)
    local strip_w = osd_w - 2 * math.floor(WINDOW_BORDER * scale)
    local timeline_top = osd_h - math.floor(WINDOW_BORDER * scale)
        - math.floor(TIMELINE_SIZE * scale) - math.floor(TIMELINE_BORDER * scale)
    local controls_top = timeline_top
        - math.floor(CONTROLS_MARGIN * scale) - math.floor(CONTROLS_SIZE * scale)
    local strip_h = math.floor(opts.height * scale)
    local strip_top = controls_top - strip_h
    if strip_top < 0 then strip_top = 0 end
    return strip_x, strip_w, strip_top, strip_h
end

local function draw_timeline_wave()
    if not state.visible or not state.peaks then return end
    local osd_w, osd_h = nil, nil
    local ok, w, h = pcall(mp.get_osd_size)
    if ok and w and h and w > 0 and h > 0 then
        osd_w, osd_h = w, h
    else
        osd_w = mp.get_property_native("osd-width")
        osd_h = mp.get_property_native("osd-height")
    end
    if not osd_w or not osd_h or osd_w <= 0 or osd_h <= 0 then
        state.visible = false
        osd("Wave timeline: no OSD size, see cache/waveforms/last-error.txt", 5)
        write_error("draw: no OSD size\n")
        return
    end
    local strip_x, strip_w, strip_top, strip_h = wave_geometry(osd_w, osd_h)
    local peaks = state.peaks
    local n = #peaks
    -- only rebuild the BGRA bytes when size or peaks changed
    local draw_key = string.format("%d|%d|%d|%d|%s", strip_x, strip_w, strip_top, strip_h, tostring(state.path))
    if draw_key == state.last_draw_key and state.last_bgra then
        mp.commandv("overlay-add", OVERLAY_ID, strip_x, strip_top, state.bgra_file, 0, "bgra", strip_w, strip_h, strip_w * 4)
        return
    end
    local centre = math.floor(strip_h / 2)
    local bg = string.char(0x14, 0x0F, 0x0B, 0xFF)
    local speech_c = string.char(0xEE, 0xD3, 0x22, 0xFF)
    local silence_c = string.char(0x40, 0x40, 0x40, 0xFF)
    local centre_c = string.char(0x80, 0x80, 0x80, 0xFF)
    local rows = {}
    for y = 0, strip_h - 1 do
        local row_parts = {}
        for x = 0, strip_w - 1 do
            local peak = 0
            if n > strip_w then
                local start_idx = math.floor(x / strip_w * n) + 1
                local end_idx = math.floor((x + 1) / strip_w * n)
                if end_idx < start_idx then end_idx = start_idx end
                for i = start_idx, end_idx do
                    local p = peaks[i] or 0
                    if p > peak then peak = p end
                end
            else
                peak = peaks[math.floor(x / strip_w * n) + 1] or 0
            end
            local bar_h = peak * (strip_h - 4)
            local bar_top = centre - bar_h / 2
            local bar_bottom = centre + bar_h / 2
            local col = bg
            if y == centre then col = centre_c end
            if peak > 0.01 and y >= bar_top and y <= bar_bottom then
                if peak < opts.speech_threshold then
                    col = silence_c
                else
                    col = speech_c
                end
            end
            row_parts[#row_parts + 1] = col
        end
        rows[#rows + 1] = table.concat(row_parts, "")
    end
    local bgra_data = table.concat(rows, "")
    -- atomic write: temp file, then rename. Never truncate the file
    -- the overlay may still reference.
    local bgra_file = utils.join_path(cache_dir(), "wave_current.bgra")
    local tmp_file = bgra_file .. ".tmp"
    local f = io.open(tmp_file, "wb")
    if not f then
        state.visible = false
        osd("Wave timeline: could not write wave image, see last-error.txt", 5)
        write_error("draw: could not open temp BGRA file: " .. tmp_file .. "\n")
        return
    end
    f:write(bgra_data)
    f:close()
    os.rename(tmp_file, bgra_file)
    state.bgra_file = bgra_file
    state.last_draw_key = draw_key
    state.last_bgra = bgra_data
    mp.commandv("overlay-add", OVERLAY_ID, strip_x, strip_top, bgra_file, 0, "bgra", strip_w, strip_h, strip_w * 4)
end

local function hide_wave()
    state.visible = false
    mp.commandv("overlay-remove", OVERLAY_ID)
end

local function show_wave()
    if state.building then
        state.pending_toggle = true
        return
    end
    state.building = true
    local ok = load_or_build()
    state.building = false
    if ok then
        state.visible = true
        draw_timeline_wave()
        local n = state.segments and #state.segments or 0
        osd(string.format("Wave timeline on - %d talks, Alt+RIGHT/LEFT jump, w hides", n), 5)
    end
    -- a w press that arrived while building: honour it now.
    if state.pending_toggle then
        state.pending_toggle = false
        if state.visible then hide_wave() end
    end
end

local function toggle_wave()
    if state.visible then
        hide_wave()
        state.user_hidden = true
        osd("Wave timeline off - press w to show again", 3)
    else
        state.user_hidden = false
        show_wave()
    end
end

local function jump_speech(direction)
    if not state.segments then
        if state.building then osd("Wave timeline: still building...", 3) return end
        show_wave()
        if not state.segments then
            osd("Wave timeline: could not build wave, see last-error.txt", 5)
            return
        end
    end
    local pos = mp.get_property_native("time-pos") or 0
    local segs = state.segments or {}
    if #segs == 0 then osd("Wave timeline: no talks found", 5) return end
    if direction > 0 then
        for _, seg in ipairs(segs) do
            if seg.start > pos then
                mp.commandv("seek", math.max(0, seg.start - 0.1), "absolute")
                return
            end
        end
        osd("Wave timeline: no more talks after here", 5)
    else
        -- inside a talk: go to that talk's start, unless already
        -- within 0.5s of it, then go to the previous talk.
        for i = #segs, 1, -1 do
            local seg = segs[i]
            if pos >= seg.start and pos <= seg["end"] then
                if pos - seg.start > 0.5 then
                    mp.commandv("seek", math.max(0, seg.start - 0.1), "absolute")
                elseif i > 1 then
                    mp.commandv("seek", math.max(0, segs[i - 1].start - 0.1), "absolute")
                else
                    mp.commandv("seek", 0, "absolute")
                end
                return
            end
            if seg["end"] < pos - 0.5 then
                mp.commandv("seek", math.max(0, seg.start - 0.1), "absolute")
                return
            end
        end
        mp.commandv("seek", 0, "absolute")
    end
end

mp.add_key_binding("w", "toggle-wave", toggle_wave)
mp.add_key_binding("W", "toggle-wave", toggle_wave)
mp.add_key_binding("Alt+RIGHT", "next-speech", function() jump_speech(1) end)
mp.add_key_binding("Alt+LEFT", "prev-speech", function() jump_speech(-1) end)
mp.register_script_message("toggle-wave", toggle_wave)

local function cancel_load_timer()
    if state.load_timer then
        pcall(function() state.load_timer:kill() end)
        state.load_timer = nil
    end
end

mp.register_event("file-loaded", function()
    cancel_load_timer()
    hide_wave()
    state.peaks = nil
    state.segments = nil
    state.path = nil
    state.duration = nil
    state.aid = current_aid()
    state.last_draw_key = nil
    state.last_bgra = nil
    if state.user_hidden then return end
    state.load_timer = mp.add_timeout(0.5, function()
        state.load_timer = nil
        if not state.shown_loaded_once then
            state.shown_loaded_once = true
            osd("Wave timeline loaded - building in timeline", 3)
        end
        show_wave()
    end)
end)

mp.register_event("end-file", function()
    cancel_load_timer()
    hide_wave()
    state.peaks = nil
    state.segments = nil
    state.path = nil
    state.duration = nil
    state.aid = nil
    state.last_draw_key = nil
    state.last_bgra = nil
end)

-- duration may arrive after file-loaded; retry once if we had no
-- duration at first attempt and the user has not hidden the wave.
mp.observe_property("duration", "number", function(_, dur)
    if dur and dur > 0 and not state.peaks and not state.user_hidden and not state.building then
        local path = mp.get_property("path")
        if path and state.path ~= path then
            show_wave()
        end
    end
end)

-- audio track change invalidates the cache (hash includes aid).
mp.observe_property("aid", "native", function(_, aid)
    if state.path and state.aid ~= aid then
        state.peaks = nil
        state.segments = nil
        state.aid = aid
        state.last_draw_key = nil
        if state.visible and not state.user_hidden then show_wave() end
    end
end)

-- One resize observer, debounced 100ms. The full BGRA
-- rewrite used to run three times per resize.
mp.observe_property("osd-dimensions", "native", function()
    if state.redraw_timer then pcall(function() state.redraw_timer:kill() end) end
    state.redraw_timer = mp.add_timeout(0.1, function()
        state.redraw_timer = nil
        draw_timeline_wave()
    end)
end)
