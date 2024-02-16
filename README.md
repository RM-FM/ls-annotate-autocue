# ls-annotation-autocue
This Liquidsoap protocol introduces EBU R128 / LUFS compliant auto cue and crossfades based on volume/loudness thresholds.

## Requirements
* Liquidsoap 2.2.4 or later
* ffprobe binary

## Usage

 Just use `annotation-autocue` the same way as the well known `annotation` protocol:

`annotation-autocue:title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`

It will do it's magic will turn the annotation/request into something like this:

`annotation:liq_amplify="-5.163 dB",liq_cue_in="0.7",liq_cue_out="158.",liq_cross_duration="4.5",liq_fade_in="0.2",liq_fade_out="4.5",liq_fade_in_curve="log",liq_fade_out_curve="exp",title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`
