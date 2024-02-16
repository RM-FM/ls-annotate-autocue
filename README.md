# ls-annotate-autocue
This Liquidsoap protocol introduces [EBU R 128](https://en.wikipedia.org/wiki/EBU_R_128#:~:text=EBU%20R%20128%20is%20a,measure%20and%20control%20programme%20loudness.) / [LUFS](https://en.wikipedia.org/wiki/LUFS#:~:text=Loudness%2C%20K%2Dweighted%2C%20relative,video%20and%20music%20streaming%20services.) compliant auto cue and crossfade based on volume/loudness thresholds.

## Features
* LUFS loudness normalization based on EBU R 128: `liq_amplify`
* Cue point detection: `liq_cue_in`, `liq_cue_out`
* Situational crossfade/overlap detection: `liq_cross_duration`, `liq_fade_in`, `liq_fade_in_curve`, `liq_fade_out`, `liq_fade_in_curve`, `liq_fade_out_delay`)

Cue/crossfade points are LUFS target difference corrected. This ensures consistent detection of cue points for both loud an quiet songs.

### Configuration options
* Target loudness LUFS
* Cue in threshold
* Cue out threshold
* Crossfade threshold

## Requirements
* Liquidsoap 2.2.4 or later
* ffprobe binary

## Usage

Simply use `annotate-autocue` the same way as the well known `annotate` protocol:

`annotate-autocue:title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`

... and it will do it's magic will turn the annotation/request into something like this:

`annotate:liq_amplify="-5.163 dB",liq_cue_in="0.7",liq_cue_out="158.",liq_cross_duration="4.5",liq_fade_in="0.2",liq_fade_out="4.5",liq_fade_in_curve="log",liq_fade_out_curve="exp",title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`
