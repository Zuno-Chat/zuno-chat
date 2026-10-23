#!/usr/bin/env python3
"""Generates the app's notification tones.

The tones are synthesized rather than sampled so they're reproducible,
tiny, licence-free, and tweakable in one place: re-run this script after
editing and commit the resulting .wav files. Deliberately plain sine
partials with a soft attack — a calm chime, not a "ringtone".

    python3 tool/generate_tones.py

Format: 22.05 kHz mono 16-bit PCM WAV. Android plays WAV natively,
and at this rate the files together are a few hundred KB — small enough
to bundle without thinking about it, and the tones are pure sines, so a
higher rate would buy nothing audible.
"""

import math
import os
import struct
import wave

RATE = 22050
CALL_TONE_RATE = 8000
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


def write(path, samples, rate=RATE):
    path = os.path.normpath(os.path.join(ROOT, path))
    frames = bytearray()
    for sample in samples:
        clipped = max(-1.0, min(1.0, sample))
        frames += struct.pack('<h', int(clipped * 32767))
    with wave.open(path, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(bytes(frames))
    print(f'{path} ({len(frames) // 1024} KB)')


A5, CS6, E6 = 880.0, 1108.73, 1318.51
C6, F6 = 1046.50, 1396.91
CALL_TONE = 425.0

# Incoming call: a rising three-note figure, twice, then a gap — played
# on loop for as long as the call rings, so the gap is what keeps it from
# feeling frantic.
write('assets/sounds/ringtone.wav', mix(4.0, [
    (0.00, note(A5, 0.45, amplitude=0.55, decay=7.0)),
    (0.26, note(CS6, 0.45, amplitude=0.55, decay=7.0)),
    (0.52, note(E6, 0.70, amplitude=0.60, decay=5.0)),
    (0.95, note(A5, 0.45, amplitude=0.55, decay=7.0)),
    (1.21, note(CS6, 0.45, amplitude=0.55, decay=7.0)),
    (1.47, note(E6, 0.90, amplitude=0.60, decay=4.0)),
]))

# New message: two notes, over almost as soon as it starts.
write('android/app/src/main/res/raw/message_tone.wav', mix(0.75, [
    (0.00, note(C6, 0.30, amplitude=0.45, decay=9.0)),
    (0.13, note(F6, 0.55, amplitude=0.45, decay=7.0)),
]))


def call_tone(start, seconds):
    return (start, tone([CALL_TONE], seconds, amplitude=0.3, rate=CALL_TONE_RATE))


write('assets/sounds/ringback.wav', mix(5.0, [
    call_tone(0.0, 1.0),
], rate=CALL_TONE_RATE), rate=CALL_TONE_RATE)

write('assets/sounds/call_waiting.wav', mix(4.0, [
    call_tone(0.0, 0.2),
    call_tone(0.8, 0.2),
], rate=CALL_TONE_RATE), rate=CALL_TONE_RATE)
