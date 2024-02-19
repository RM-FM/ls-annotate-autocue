# Initialize settings for annotate-autocue protocol
let settings.protocol.annotate_autocue = settings.make.protocol("annotate-autocue")

let settings.protocol.annotate_autocue.lufs_target =
  settings.make(description="Loudness target in LUFS (float)", -18.0)
  
let settings.protocol.annotate_autocue.cue_in_thresh =
  settings.make(description="Threshold for Cue In relative to LUFS (float)", -34.0)
  
let settings.protocol.annotate_autocue.cue_out_thresh =
  settings.make(description="Threshold for Cue Out relative to LUFS (float)", -42.0)
  
let settings.protocol.annotate_autocue.cross_thresh =
  settings.make(description="Threshold for Crossfade start relative to LUFS (float)", -7.0)
  
let settings.protocol.annotate_autocue.max_overlap =
  settings.make(description="Max. allowed overlap/crossfade in seconds (float)", 6.0)

# Change default setting if needed
settings.protocol.annotate_autocue.lufs_target := -16.0

# Function: Get data from ffmpeg.filter.ebur128
def ebur128_frames(uri) =
  r = request.create(uri)
  
  if request.resolve(r) then
  
  s = request.once(r)
  if s.resolve() then
    
    frames = ref([])

    def ebur128(s) =
      def mk_filter(graph) =
        let {audio = a} = source.tracks(s)
        a = ffmpeg.filter.audio.input(graph, a)
        let ([a], _) = ffmpeg.filter.ebur128(metadata=true, graph, a)
        a = ffmpeg.filter.audio.output(graph, a)
        source({audio=a, metadata=track.metadata(a)})
      end

      ffmpeg.filter.create(mk_filter)
      
    end

    s = ebur128(s)
    s = source.on_metadata(s, fun (m) -> frames := [...frames(), m])
    source.drop(s)

    frames()
  else
    log(level=1,label="annotate-autocue","Couldn't resolve source for uri: #{uri}")
    []
  end
  else
    log(level=1,label="annotate-autocue","Couldn't resolve request for uri: #{uri}")
    []
  end
end

# Do the auto cue magic
def get_autocue(uri,lufs_target,cue_in_thresh,cue_out_thresh,cross_thresh,max_overlap) =

  cue_meta_response = ref("")

  # Run ffprobe EBU R128 filter to retrieve loudness data per frame 
  frames = ebur128_frames(uri)

  ffprobe_success = ref(true)
  try
    if list.length(frames) <= 0 then
      log(level=1,label="annotate-autocue","Couldn't retrieve data from ffprobe. Make sure ffprobe binary is installed and media file is valid. Skipping autocue...")
      ffprobe_success := false
    end
  catch _ do
    log(level=1,label="annotate-autocue","Couldn't parse data from ffprobe. Make sure ffprobe binary is installed. Skipping autocue...")
    ffprobe_success := false
  end

  if ffprobe_success() then
    # Get the 2nd last frame which is the last with loudness data
    frame = list.nth(frames,list.length(frames)-2)
    
    # Get the Integrated Loudness from the last frame (overall loudness)
    lufs = float_of_string(list.assoc(default=string(lufs_target), "lavfi.r128.I", frame))

    # Calc LUFS difference to target for liq_amplify
    lufs_correction = lufs_target - lufs
    
    # Create dB thresholds relative to LUFS target
    lufs_cue_in_thresh = lufs + cue_in_thresh
    lufs_cue_out_thresh = lufs + cue_out_thresh
    lufs_cross_thresh = lufs + cross_thresh
    
    log(level=4,label="annotate-autocue","lufs_correction: #{lufs_correction}")
    log(level=4,label="annotate-autocue","adj_cue_in_thresh: #{lufs_cue_in_thresh}")
    log(level=4,label="annotate-autocue","adj_cue_out_thresh: #{lufs_cue_out_thresh}")
    log(level=4,label="annotate-autocue","adj_cross_thresh: #{lufs_cross_thresh}")
    
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
      db_level = list.assoc(default="nan", string("lavfi.r128.M"), frame)
      current_ts := float_of_string(list.assoc(default="0.", "lavfi.liq.pts", frame))

      # Process only valid level values
      if db_level != "nan" then
        db_level = float_of_string(db_level)

        if db_level > lufs_cue_in_thresh and cue_in_found() == false then
          # First time exceeding threshold. Set cue in to timestamp of previous frame.
          cue_in := last_ts()
          cue_in_found := true
        end
        if db_level > lufs_cue_out_thresh then
          # Cue out: Stick with the latest timestamp where level still exceeds threshold
          cue_out := current_ts()
        end      
        if db_level > lufs_cross_thresh then
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
    duration = float_of_string(list.assoc(default="0.", "lavfi.liq.pts", frame)) + float_of_string(list.assoc(default="0.", "lavfi.liq.duration", frame))
    
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
      
    # Force minimum overlap to avoid invalid crossfades
    cross_dur := max(cross_dur(),0.1)
    fade_in := max(fade_in(),0.1)
    fade_out := max(fade_out(),0.1)
    
    # Build annotation compliant string with metadata
    cue_meta = ref([])

    def append_meta(m) =
      cue_meta := [...cue_meta(), m]
    end

    append_meta("liq_amplify=\"#{string(lufs_correction)} dB\"")
    if cue_in() > 0. then append_meta("liq_cue_in=\"#{cue_in()}\"") end
    if cue_out() > 0. then append_meta("liq_cue_out=\"#{cue_out()}\"") end
    append_meta("liq_cross_duration=\"#{cross_dur()}\"")
    append_meta("liq_fade_in=\"#{fade_in()}\"")
    append_meta("liq_fade_out=\"#{fade_out()}\"")
    if fade_out_delay() > 0. then
      append_meta("liq_fade_out_delay=\"#{fade_out_delay()}\"")
      fade_out_curve := "log"
    end
    append_meta("liq_fade_in_curve=\"#{fade_in_curve()}\"")
    append_meta("liq_fade_out_curve=\"#{fade_out_curve()}\"")

    cue_meta_response := string.concat(separator=",", cue_meta())
  
    log(level=3,label="annotate-autocue","#{cue_meta_response()}")
    
  end
  
  cue_meta_response()
end

# Define annotate-autocue protocol
def annotate_autocue_protocol(~rlog=_,~maxtime=_,arg) =

  # Get protocol settings
  lufs_target = settings.protocol.annotate_autocue.lufs_target()
  cue_in_thresh = settings.protocol.annotate_autocue.cue_in_thresh()
  cue_out_thresh = settings.protocol.annotate_autocue.cue_out_thresh()
  cross_thresh = settings.protocol.annotate_autocue.cross_thresh()
  max_overlap = settings.protocol.annotate_autocue.max_overlap()

  log(level=4,label="annotate-autocue","lufs_target: #{lufs_target}")
  log(level=4,label="annotate-autocue","cue_in_thresh: #{cue_in_thresh}")
  log(level=4,label="annotate-autocue","cue_out_thresh: #{cue_out_thresh}")
  log(level=4,label="annotate-autocue","cross_thresh: #{cross_thresh}")
  log(level=4,label="annotate-autocue","max_overlap: #{max_overlap}")
  
  skip_autocue = ref(false)
  
  # Parse annotation string
  annotate_parts =
    try
      string.annotate.parse(arg)
    catch _ do
      ([], arg)
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

  autocue_annotate = ref("")
  if skip_autocue() == false then
    # URI extraction
    media_uri = snd(annotate_parts)
    # Get the auto cue annotation string
    cue_meta = get_autocue(media_uri,lufs_target,cue_in_thresh,cue_out_thresh,cross_thresh,max_overlap)
    # Rebuild and return annotation string
    autocue_annotate := "annotate:#{cue_meta}:#{arg}"   
    log(level=4,label="annotate-autocue","#{autocue_annotate}")
  else
    autocue_annotate := "annotate:#{arg}"   
  end

  ["#{autocue_annotate()}"]
  
end

# Add annotate-autocue protocol
protocol.add(
    "annotate-autocue",
    annotate_autocue_protocol,
    doc="Adding auto cues/crossfade to annotation",
    syntax="annotate-autocue:uri"
)
