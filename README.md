# ls-annotate-autocue

> [!CAUTION]
> This repo has been discontinued.

> [!NOTE]
> The entire autocue functionality was implemented natively in Liquidsoap natively. This repo has served as a template and has now been discontinued. Further development and any bug fixes will take place directly in Liquisoap.
>
> Available with Liquidsoap version 2.2.5 or later:
> - Metadata resolver: `enable_autocue_metadata()`
> - Protocol: `autocue:`

> [!TIP]
> Please check the official Liquidsoap documenation for more details:
> - https://www.liquidsoap.info/doc-dev/reference.html#enable_autocue_metadata
> - https://www.liquidsoap.info/doc-dev/reference.html#settings.autocue
> - https://www.liquidsoap.info/doc-dev/protocols.html#autocue

## Features

This Liquidsoap protocol introduces [EBU R 128](https://en.wikipedia.org/wiki/EBU_R_128#:~:text=EBU%20R%20128%20is%20a,measure%20and%20control%20programme%20loudness.) / [LUFS](https://en.wikipedia.org/wiki/LUFS#:~:text=Loudness%2C%20K%2Dweighted%2C%20relative,video%20and%20music%20streaming%20services.) compliant normalization and auto cue/crossfade detection based on loudness thresholds.

* LUFS loudness normalization based on EBU R 128: `liq_amplify`
* Cue point detection: `liq_cue_in`, `liq_cue_out`
* Situational crossfade/overlap detection: `liq_cross_duration`, `liq_fade_in`, `liq_fade_in_curve`, `liq_fade_out`, `liq_fade_out_curve`, `liq_fade_out_delay`

Cue/crossfade points are calculated relative to LUFS target loudness. This ensures consistent detection of cue points for both loud an quiet songs.

### Configuration options
* LUFS target loudness
* Cue in threshold
* Cue out threshold
* Crossfade threshold
* Maximum crossfade/overlap duration

## Requirements
* [Liquidsoap 2.2.5 (Rolling Release 2.2.x)](https://github.com/savonet/liquidsoap/releases)

## Usage

Simply use `annotate-autocue` the same way as the well known `annotate` protocol:

`annotate-autocue:title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`

... and it will do it's magic turn the annotation/request into something like this:

`annotate:liq_amplify="-5.163 dB",liq_cue_in="0.7",liq_cue_out="158.",liq_cross_duration="4.5",liq_fade_in="0.2",liq_fade_out="4.5",liq_fade_in_curve="log",liq_fade_out_curve="exp",title="Talkin' Bout A Revolution",artist="Tracy Chapman":/path/tracy_chapman_-_talkin_bout_a_revolution.mp3`
