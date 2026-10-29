#!/usr/bin/env python3
"""Generates the app's notification tones.

The tones are synthesized rather than sampled so they're reproducible,
tiny, licence-free, and tweakable in one place: re-run this script after
editing and commit the resulting files. Deliberately plain sine
partials with a soft attack — a calm chime, not a "ringtone".

    python3 tool/generate_tones.py

Each tone is written in the most compact format its player takes: Ogg
Vorbis for Android's media players (stored uncompressed in the APK, as
they need), 8 kHz mu-law WAV for call tones (Android decodes them itself
into call audio) and IMA4 CAF for iOS alert and CallKit sounds. Needs
macOS for afconvert and vorbis-tools (brew install vorbis-tools).
"""

import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 22050
CALL_TONE_RATE = 8000
RING_SECONDS = 4.0
IOS_SOUND_LIMIT = 30.0
ROOT = os.path.join(os.path.dirname(__file__), '..')


def note(freq, seconds, amplitude=0.5, decay=6.0, harmonic=0.25):
    """One struck note: sine plus a quiet octave, exponential decay."""
    out = []
    attack = int(0.006 * RATE)  # a few ms, so it doesn't click
    total = int(seconds * RATE)
    for i in range(total):
        t = i / RATE
        env = math.exp(-decay * t)
        if i < attack:
            env *= i / attack
        sample = math.sin(2 * math.pi * freq * t)
        sample += harmonic * math.sin(4 * math.pi * freq * t)
        out.append(amplitude * env * sample / (1 + harmonic))
    return out


def tone(freqs, seconds, amplitude=0.25, fade=0.02, rate=RATE):
    """A steady, level tone (telephony-style), with fades at both ends."""
    out = []
    total = int(seconds * rate)
    fade_samples = max(1, int(fade * rate))
    for i in range(total):
        t = i / rate
        env = min(1.0, i / fade_samples, (total - i) / fade_samples)
        sample = sum(math.sin(2 * math.pi * f * t) for f in freqs) / len(freqs)
        out.append(amplitude * env * sample)
    return out


def mix(length_seconds, parts, rate=RATE):
    """Lays [(start_seconds, samples), ...] onto one buffer."""
    buffer = [0.0] * int(length_seconds * rate)
    for start, samples in parts:
        offset = int(start * rate)
        for i, sample in enumerate(samples):
            index = offset + i
            if index < len(buffer):
                buffer[index] += sample
    return buffer


def vorbis(source, target):
    return ['oggenc', '-Q', '-q', '10', '--serial', '1', '-o', target, source]


def mu_law_wav(source, target):
    return ['afconvert', '-f', 'WAVE', '-d', 'ulaw', '--no-filler', source, target]


def ima4_caf(source, target):
    return ['afconvert', '-f', 'caff', '-d', 'ima4', '--no-filler', source, target]


def write_pcm(path, samples, rate):
    frames = bytearray()
    for sample in samples:
        clipped = max(-1.0, min(1.0, sample))
        frames += struct.pack('<h', int(clipped * 32767))
    with wave.open(path, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(bytes(frames))


def write(path, samples, encoder, rate=RATE):
    path = os.path.normpath(os.path.join(ROOT, path))
    with tempfile.TemporaryDirectory() as scratch:
        source = os.path.join(scratch, 'tone.wav')
        write_pcm(source, samples, rate)
        subprocess.run(encoder(source, path), check=True)
    print(f'{path} ({os.path.getsize(path) / 1024:.1f} KB)')


missing = [tool for tool in ('afconvert', 'oggenc') if shutil.which(tool) is None]
if missing:
    sys.exit(f'Missing {", ".join(missing)}: run on macOS with vorbis-tools installed.')


A5, CS6, E6 = 880.0, 1108.73, 1318.51
C6, F6 = 1046.50, 1396.91
CALL_TONE = 425.0

# Incoming call: a rising three-note figure, twice, then a gap — played
# on loop for as long as the call rings, so the gap is what keeps it from
# feeling frantic.
ringtone = mix(RING_SECONDS, [
    (0.00, note(A5, 0.45, amplitude=0.55, decay=7.0)),
    (0.26, note(CS6, 0.45, amplitude=0.55, decay=7.0)),
    (0.52, note(E6, 0.70, amplitude=0.60, decay=5.0)),
    (0.95, note(A5, 0.45, amplitude=0.55, decay=7.0)),
    (1.21, note(CS6, 0.45, amplitude=0.55, decay=7.0)),
    (1.47, note(E6, 0.90, amplitude=0.60, decay=4.0)),
])
write('assets/sounds/ringtone.ogg', ringtone, vorbis)
fallback_loops = math.ceil(IOS_SOUND_LIMIT / RING_SECONDS) - 1
write('ios/Runner/fallback_ring.caf', ringtone * fallback_loops, ima4_caf)
write('ios/Runner/silent_ring.caf', [0.0] * CALL_TONE_RATE, ima4_caf, rate=CALL_TONE_RATE)

# New message: two notes, over almost as soon as it starts.
message_tone = mix(0.75, [
    (0.00, note(C6, 0.30, amplitude=0.45, decay=9.0)),
    (0.13, note(F6, 0.55, amplitude=0.45, decay=7.0)),
])
write('android/app/src/main/res/raw/message_tone.ogg', message_tone, vorbis)
write('ios/Runner/message_tone.caf', message_tone, ima4_caf)


def call_tone(start, seconds):
    return (start, tone([CALL_TONE], seconds, amplitude=0.3, rate=CALL_TONE_RATE))


write('assets/sounds/ringback.wav', mix(5.0, [
    call_tone(0.0, 1.0),
], rate=CALL_TONE_RATE), mu_law_wav, rate=CALL_TONE_RATE)

write('assets/sounds/call_waiting.wav', mix(4.0, [
    call_tone(0.0, 0.2),
    call_tone(0.8, 0.2),
], rate=CALL_TONE_RATE), mu_law_wav, rate=CALL_TONE_RATE)
