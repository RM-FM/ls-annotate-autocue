# ls-annotate-autocue
This Liquidsoap protocol introduces EBU R128 / LUFS compliant auto cue and crossfades based on volume/loudness thresholds. Just use it as the well known `annotate` protocol:

`annotate_autocue:title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`

It will do it's magic will turn the annotation/request into something like this:

`annotate:liq_amplify="-5.163 dB",liq_cue_in="0.7",liq_cue_out="158.",liq_cross_duration="4.5",liq_fade_in="0.2",liq_fade_out="4.5",liq_fade_in_curve="log",liq_fade_out_curve="exp",title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`
