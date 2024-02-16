# Initilize settings for annotate-autocue protocol
let settings.protocol.annotate-autocue = settings.make.protocol("annotate-autocue")

let settings.protocol.annotate-autocue.lufs_target =
  settings.make(description="Loudness target in LUFS (float)", -18.0)
  
let settings.protocol.annotate-autocue.cue_in_thresh =
  settings.make(description="Threshold for Cue In in dB (float)", -30.0)
  
let settings.protocol.annotate-autocue.cue_out_thresh =
  settings.make(description="Threshold for Cue In in dB (float)", -38.0)
  
let settings.protocol.annotate-autocue.cross_thresh =
  settings.make(description="Threshold for Crossfade start in dB (float)", -14.0)
  
let settings.protocol.annotate-autocue.max_overlap =
  settings.make(description="Max. allowed overlap/crossfade in seconds (float)", 6.0)

# Change default setting
settings.protocol.annotate-autocue.lufs_target := -16.0

# Do the auto cue magic
def get_autocue(filepath,lufs_target,cue_in_thresh,cue_out_thresh,cross_thresh,max_overlap) =

  # Run ffprobe EBU R128 filter to retrieve loudness data per frame 
  command = "ffprobe -v quiet -f lavfi -i amovie=#{string.quote(filepath)},ebur128=metadata=1 -show_frames -of json"
  result = process.read.lines(command)
  json_payload = string.concat(result)
  
  log(level=4,label="annotate-autocue","#{command}")
  log(level=4,label="annotate-autocue","#{json_payload}")
  
  # Parse required data from JSON string
  let json.parse ({
    frames = [{
      best_effort_timestamp_time,
      duration_time,
	  tags
    }]
  } : {
    frames: [{
      best_effort_timestamp_time: string,
      duration_time: string?,
	  tags: {
        "lavfi.r128.I" as lavfi_r128_I: string?,
        "lavfi.r128.M" as lavfi_r128_M: string?
	  }?
    }]
  }) = json_payload

  # Get the 2nd last frame which is the last with loudness data
  frame = list.nth(frames,list.length(frames)-2)
  
  # Get the Integrated Loudness from the last frame (overall loudness)
  lufs = float_of_string(frame.tags.lavfi_r128_I ?? string(lufs_target))
  
  # Calc LUFS difference to target for liq_amplify
  lufs_correction = lufs_target - lufs
  
  # Adjust Cue dB thresholds by LUFS correction
  adj_cue_in_thresh = cue_in_thresh + lufs_correction
  adj_cue_out_thresh = cue_out_thresh + lufs_correction
  adj_cross_thresh = cross_thresh + lufs_correction
  
  log(level=4,label="annotate-autocue","lufs_correction: #{lufs_correction}")
  log(level=4,label="annotate-autocue","adj_cue_in_thresh: #{adj_cross_thresh}")
  log(level=4,label="annotate-autocue","adj_cue_out_thresh: #{adj_cross_thresh}")
  log(level=4,label="annotate-autocue","adj_cross_thresh: #{adj_cross_thresh}")
  
  # Set cue/fade defaults
  cue_in = ref(0.)
  cue_out = ref(0.)
  cross_cue = ref(0.)
  fade_in = ref(0.)
  fade_in_curve = ref("log")
  fade_out = ref(0.)
  fade_out_delay = ref(0.)
  fade_out_curve = ref("exp")
  cross_dur = ref(0.)

  # Extract timestamps for cue points
  # Iterate over loudness data frames and set cue points based on db thresholds
  cue_in_found = ref(false)
  last_ts = ref(0.)
  current_ts = ref(0.)
  def find_cues(frame) =
    # Get current frame loudness level and timestamp
    db_level = (frame.tags.lavfi_r128_M ?? "nan")
    current_ts := float_of_string(frame.best_effort_timestamp_time ?? "0.")
    # Process only valid level values
    if db_level != "nan" then
      db_level = float_of_string(db_level)
      if db_level > adj_cue_in_thresh and cue_in_found() == false then
        # First time exceeding threshold. Set cue in to timestamp of previous frame.
        cue_in := last_ts()
        cue_in_found := true
      end
      if db_level > adj_cue_out_thresh then
        # Cue out: Stick with the latest timestamp where level still exceeds threshold
        cue_out := current_ts()
      end      
      if db_level > adj_cross_thresh then
        # Absolute crossfade cue: Stick with the latest timestamp where level still exceeds threshold
        cross_cue := current_ts()
      end
    end
    # Update last timestamp value with current
    last_ts := current_ts()
  end
  list.iter(find_cues, frames)
  
  # Get very last frame for precise track duration
  frame = list.last(frames)
  duration = float_of_string(frame.best_effort_timestamp_time ?? "0.") + float_of_string(string((frame.duration_time ?? "0.")))
  
  # Finalize cue/cross/fade values now...
  
  # Calc cross/overlap duration
  if cross_cue() + 0.1 < duration then
    if cue_out() > 0. then
      cross_dur := cue_out() - cross_cue()
    else
      cross_dur := duration - cross_cue()
    end
  end
  
  # Add some margin to cue in
  cue_in := cue_in() - 0.1  
  # Avoid hard cuts on cue in
  if cue_in() > 0.2 then
    fade_in := 0.2
    cue_in := cue_in() - 0.2
  end
  # Ignore super short cue in
  if cue_in() <= 0.2 then
    fade_in := 0.
    cue_in := 0.
  end
  # Catch invalid cue out values
  if cue_out() <= cue_in() then cue_out := 0. end 
  # Set fade out equal to crossfade/overlap
  if cross_dur() > 0. then fade_out := cross_dur() end
  
  # Limit overlap duration to maximum
  if cross_dur() > max_overlap then
    cue_shift = cross_dur() - max_overlap
    cue_out := cue_out() - cue_shift
    cross_dur := max_overlap
    fade_out := max_overlap
  end  
  
  # Delay fade out slighly on short overlaps
  if cue_out() > 0. and cross_dur() < 2.0 then
    fade_out := max(cross_dur()/2., 0.1)
    fade_out_delay := fade_out()
  end
  
  # Force minimal overlap to prevent invalid crossfade
  if cross_dur() <= 0. then
    cross_dur := 0.2
    fade_out := 0.
    fade_out_delay := 0.2
  end
  
  # Build annotation compliant string with metadata
  cue_meta = ref("")
  cue_meta := "#{cue_meta()}liq_amplify=\"#{string(lufs_correction)} dB\","
  if cue_in() > 0. then cue_meta := "#{cue_meta()}liq_cue_in=\"#{cue_in()}\"," end
  if cue_out() > 0. then cue_meta := "#{cue_meta()}liq_cue_out=\"#{cue_out()}\"," end
  cue_meta := "#{cue_meta()}liq_cross_duration=\"#{cross_dur()}\","
  cue_meta := "#{cue_meta()}liq_fade_in=\"#{fade_in()}\","
  cue_meta := "#{cue_meta()}liq_fade_out=\"#{fade_out()}\","
  if fade_out_delay() > 0. then
    cue_meta := "#{cue_meta()}liq_fade_out_delay=\"#{fade_out_delay()}\","
    fade_out_curve := "log"
  end
  cue_meta := "#{cue_meta()}liq_fade_in_curve=\"#{fade_in_curve()}\","  
  cue_meta := "#{cue_meta()}liq_fade_out_curve=\"#{fade_out_curve()}\","  

  log(level=3,label="annotate-autocue","#{string.sub(cue_meta(),start=0,length=string.length(cue_meta())-1)}")
  
  # Return metadata for annotation injection
  cue_meta()
  
end

# Define annotate-autocue protocol
def annotate-autocue_protocol(~rlog=_,~maxtime=_,arg) =

  # Get protocol settings
  lufs_target = settings.protocol.annotate-autocue.lufs_target()
  cue_in_thresh = settings.protocol.annotate-autocue.cue_in_thresh()
  cue_out_thresh = settings.protocol.annotate-autocue.cue_out_thresh()
  cross_thresh = settings.protocol.annotate-autocue.cross_thresh()
  max_overlap = settings.protocol.annotate-autocue.max_overlap()

  log(level=4,label="annotate-autocue","lufs_target: #{lufs_target}")
  log(level=4,label="annotate-autocue","cue_in_thresh: #{cue_in_thresh}")
  log(level=4,label="annotate-autocue","cue_out_thresh: #{cue_out_thresh}")
  log(level=4,label="annotate-autocue","cross_thresh: #{cross_thresh}")
  log(level=4,label="annotate-autocue","max_overlap: #{max_overlap}")
  
  skip_autocue = ref(false)
  
  # Parse annotation string
  annotate_parts = string.annotate.parse(arg)
  
  # Filename extraction
  uri_parts = string.split(separator=":",snd(annotate_parts))
  filename = list.last(uri_parts)
  filepath = ref(filename)
  
  # Workaround for Azuracast Stations
  try
    filepath := "#{station_media_dir}/#{filename}"
    log(level=4,label="annotate-autocue","Azuracast station! Adding station media directory to filename: #{station_media_dir}/#{filename}")
  catch _ do
    log(level=4,label="annotate-autocue","Not an Azuracast station! Using filename as provided in annotation: #{filename}")
  end
  
  # Checking for existing cue/cross/fade values
  def find_existing_meta(part) =
    metadata_key = fst(part)
    skip_autocue := false
    if r/liq_(cue|cross|fade)/i.test((metadata_key)) then
      log(level=3,label="annotate-autocue","Skipping autocue because of existing cue/cross/fade metadata: #{part}")
      skip_autocue := true
    end
    skip_autocue()
  end
  skip_autocue := list.exists(find_existing_meta, fst(annotate_parts))  
  
  if file.exists(filepath()) == false then
    log(level=1,label="annotate-autocue","Autocue aborted! File not found: #{filepath()}")
    skip_autocue := true
  end
  
  autocue_annotate = ref("")
  if skip_autocue() == false then
    # Get the auto cue annotation string
    cue_meta = get_autocue(filepath(),lufs_target,cue_in_thresh,cue_out_thresh,cross_thresh,max_overlap)
    # Rebuild and return annotation string
    autocue_annotate := "annotate:#{cue_meta}#{arg}"   
    log(level=4,label="annotate-autocue","#{autocue_annotate}")
  else
    autocue_annotate := "annotate:#{arg}"   
  end

  ["#{autocue_annotate()}"]
  
end

# Add annotate-autocue protocol
protocol.add(
    "annotate-autocue",
    annotate-autocue_protocol,
    doc="Adding auto cues/crossfade to annotation",
    syntax="annotate-autocue:uri"
)