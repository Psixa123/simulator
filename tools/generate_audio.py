"""Synthesizes Storm Catcher Simulator's sound effects and music loop (no dependencies).

Usage:  python tools/generate_audio.py
Output: assets/audio/*.wav  (upload these to Roblox, then paste the IDs into
        src/shared/Config/Sounds.luau)
"""

import array
import math
import os
import random
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
TAU = 2 * math.pi

random.seed(7)


def silence(seconds, sr=SR):
    return [0.0] * int(seconds * sr)


def save(name, samples, sr=SR, peak=0.9):
    top = max(1e-9, max(abs(s) for s in samples))
    scale = peak / top * 32767
    data = array.array("h", (int(max(-32767, min(32767, s * scale))) for s in samples))
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sr)
        handle.writeframes(data.tobytes())
    print(f"  {name:18s} {len(samples) / sr:5.2f}s  {os.path.getsize(path) / 1024:7.0f} KB")


def tone(out, start, dur, freq, amp, decay=6.0, attack=0.004, freq_end=None, harmonics=(), fm=None,
         sr=SR, wrap=False, release=0.012):
    """Adds a (optionally sweeping / FM) tone with an exponential decay envelope."""
    count = int(dur * sr)
    first = int(start * sr)
    size = len(out)
    phase = 0.0
    for i in range(count):
        t = i / sr
        progress = i / count
        if freq_end is None:
            f = freq
        else:
            f = freq * (freq_end / freq) ** progress  # exponential sweep
        phase += TAU * f / sr
        level = amp * min(1.0, t / attack) * math.exp(-t * decay)
        tail = (count - i) / (release * sr)
        if tail < 1:
            level *= tail
        if fm:
            ratio, index = fm
            value = math.sin(phase + index * math.exp(-t * decay * 1.5) * math.sin(phase * ratio))
        else:
            value = math.sin(phase)
        for multiple, weight in harmonics:
            value += weight * math.sin(phase * multiple)
        position = first + i
        if wrap:
            position %= size
        elif position >= size:
            break
        out[position] += level * value


def noise(out, start, dur, amp, decay=20.0, lowpass=0.3, highpass=0.0, attack=0.002, sr=SR, wrap=False):
    """Adds filtered white noise. lowpass/highpass are one-pole coefficients (0..1)."""
    count = int(dur * sr)
    first = int(start * sr)
    size = len(out)
    low = 0.0
    slow = 0.0
    for i in range(count):
        t = i / sr
        white = random.uniform(-1, 1)
        low += lowpass * (white - low)
        value = low
        if highpass > 0:
            slow += highpass * (low - slow)
            value = low - slow
        level = amp * min(1.0, t / attack) * math.exp(-t * decay)
        tail = (count - i) / (0.01 * sr)
        if tail < 1:
            level *= tail
        position = first + i
        if wrap:
            position %= size
        elif position >= size:
            break
        out[position] += level * value


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------
def make_click():
    out = silence(0.09)
    tone(out, 0, 0.07, 1250, 0.9, decay=55, freq_end=720)
    noise(out, 0, 0.012, 0.25, decay=200, lowpass=0.8)
    return out


def make_pop():
    out = silence(0.32)
    tone(out, 0, 0.11, 260, 0.9, decay=22, freq_end=1050)
    noise(out, 0.01, 0.25, 0.4, decay=16, lowpass=0.12)
    tone(out, 0.05, 0.2, 1568, 0.18, decay=14, fm=(2.0, 1.5))
    return out


def make_error():
    out = silence(0.4)
    square = ((3, 0.33), (5, 0.2), (7, 0.12))
    tone(out, 0, 0.14, 196, 0.6, decay=4, harmonics=square)
    tone(out, 0.15, 0.22, 147, 0.6, decay=5, harmonics=square)
    return out


def make_sell():
    out = silence(0.95)
    notes = [1046.5, 1318.5, 1568.0, 2093.0, 2637.0, 3136.0]
    for index, freq in enumerate(notes):
        tone(out, index * 0.055, 0.45, freq, 0.5, decay=11, fm=(3.01, 2.2))
    tone(out, 0.33, 0.6, 4186.0, 0.12, decay=7)
    noise(out, 0, 0.3, 0.08, decay=12, lowpass=0.9, highpass=0.3)
    return out


def make_success():
    out = silence(1.25)
    soft = ((2, 0.3), (3, 0.1))
    for index, freq in enumerate([523.25, 659.25, 783.99, 1046.5]):
        tone(out, index * 0.085, 0.7, freq, 0.5, decay=5.5, harmonics=soft)
    for freq in (1046.5, 1318.5, 1568.0):
        tone(out, 0.36, 0.85, freq, 0.22, decay=4.5, fm=(2.0, 1.0))
    return out


def make_hatch():
    out = silence(1.3)
    noise(out, 0, 0.07, 0.9, decay=45, lowpass=0.7, highpass=0.15)
    noise(out, 0.05, 0.05, 0.6, decay=60, lowpass=0.9, highpass=0.3)
    tone(out, 0.06, 0.34, 320, 0.45, decay=3, freq_end=1500, harmonics=((2, 0.25),))
    for index, freq in enumerate([1318.5, 1661.2, 1975.5, 2637.0]):
        tone(out, 0.36 + index * 0.04, 0.8, freq, 0.3, decay=5, fm=(3.0, 1.8))
    noise(out, 0.36, 0.5, 0.1, decay=8, lowpass=0.95, highpass=0.4)
    return out


def make_alarm():
    seconds = 1.9
    out = silence(seconds)
    phase = 0.0
    count = len(out)
    for i in range(count):
        t = i / SR
        freq = 700 + 170 * math.sin(TAU * 2.6 * t)
        phase += TAU * freq / SR
        value = math.sin(phase) + 0.35 * math.sin(phase * 2) + 0.2 * math.sin(phase * 3)
        level = min(1.0, t / 0.05) * min(1.0, (seconds - t) / 0.25)
        out[i] = 0.7 * level * value
    return out


def make_vacuum_loop():
    """Seamless 2 second loop: motor hum + airy whoosh."""
    seconds = 2.0
    count = int(seconds * SR)
    fade = int(0.25 * SR)
    out = [0.0] * count

    # Hum: every frequency completes a whole number of cycles in the loop
    for i in range(count):
        t = i / SR
        wobble = 1 + 0.12 * math.sin(TAU * 4 * t)
        hum = 0.34 * math.sin(TAU * 110 * t) + 0.2 * math.sin(TAU * 220 * t) + 0.1 * math.sin(TAU * 330 * t)
        whistle = 0.05 * math.sin(TAU * 880 * t + 1.5 * math.sin(TAU * 6 * t))
        out[i] = (hum + whistle) * wobble

    # Airy noise, cross-faded so the end flows into the start
    raw = []
    low = 0.0
    slow = 0.0
    for _ in range(count + fade):
        white = random.uniform(-1, 1)
        low += 0.35 * (white - low)
        slow += 0.02 * (low - slow)
        raw.append(low - slow)
    for i in range(count):
        if i < fade:
            mix = i / fade
            value = raw[i] * mix + raw[count + i] * (1 - mix)
        else:
            value = raw[i]
        out[i] += 0.55 * value
    return out


# ---------------------------------------------------------------------------
# Music: a calm, seamless 40 second loop (C - Am - F - G, 96 BPM)
# ---------------------------------------------------------------------------
NOTE = {
    "C2": 65.41, "F1": 43.65, "G1": 49.00, "A1": 55.00,
    "F3": 174.61, "G3": 196.00, "A3": 220.00, "B3": 246.94,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00, "B4": 493.88,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00, "C6": 1046.50,
}


def make_music_loop():
    sr = 32000
    beat = 60 / 96
    bars = 16
    seconds = bars * 4 * beat
    out = silence(seconds, sr)

    chords = [
        ("C2", ["C4", "E4", "G4", "B4"]),
        ("A1", ["A3", "C4", "E4", "G4"]),
        ("F1", ["F3", "A3", "C4", "E4"]),
        ("G1", ["G3", "B3", "D4", "E4"]),
    ]

    for cycle in range(2):
        for index, (bass, notes) in enumerate(chords):
            start_beat = (cycle * 4 + index) * 8
            start = start_beat * beat
            length = 8 * beat

            # Pad
            for name in notes:
                tone(out, start, length + 1.4, NOTE[name], 0.085, decay=0.25, attack=0.9,
                     harmonics=((2, 0.22), (3, 0.06)), sr=sr, wrap=True, release=1.2)

            # Bass: beats 1 and 3 of both bars, plus a pickup
            for offset, dur in ((0, 1.6), (2.5, 0.5), (4, 1.6), (6, 1.0), (7, 0.9)):
                tone(out, start + offset * beat, dur * beat, NOTE[bass] * 2, 0.3, decay=2.2,
                     harmonics=((2, 0.3),), sr=sr, wrap=True, attack=0.01)

            # Plucked arpeggio (eighth notes, an octave up)
            pattern = [0, 1, 2, 3, 2, 1, 2, 3]
            for step in range(16):
                name = notes[pattern[step % 8]]
                amp = 0.1 if step % 2 == 0 else 0.07
                tone(out, start + step * beat / 2, 0.55, NOTE[name] * 2, amp, decay=7,
                     harmonics=((3, 0.11), (5, 0.04)), sr=sr, wrap=True)

            # Drums
            for bar_beat in range(8):
                when = start + bar_beat * beat
                if bar_beat % 2 == 0:
                    tone(out, when, 0.22, 120, 0.42, decay=14, freq_end=45, sr=sr, wrap=True)
                else:
                    noise(out, when, 0.12, 0.2, decay=28, lowpass=0.5, highpass=0.2, sr=sr, wrap=True)
                noise(out, when + beat / 2, 0.04, 0.07, decay=70, lowpass=0.95, highpass=0.6, sr=sr, wrap=True)

    # Melody on the second pass (bars 9-16): (beat, length in beats, note)
    melody = [
        (0, 1, "E5"), (1, 1, "G5"), (2, 2, "A5"), (4, 1, "G5"), (5, 1, "E5"), (6, 2, "D5"),
        (8, 1, "C5"), (9, 1, "E5"), (10, 2, "A5"), (12, 1.5, "G5"), (13.5, 0.5, "E5"), (14, 2, "C5"),
        (16, 1, "A4"), (17, 1, "C5"), (18, 2, "E5"), (20, 1, "D5"), (21, 1, "C5"), (22, 2, "A4"),
        (24, 1, "B4"), (25, 1, "D5"), (26, 2, "G5"), (28, 1, "E5"), (29, 1, "D5"), (30, 2, "C5"),
    ]
    for start_beat, length, name in melody:
        when = (32 + start_beat) * beat
        tone(out, when, length * beat + 0.5, NOTE[name], 0.16, decay=2.6, fm=(2.0, 1.2), sr=sr, wrap=True)
        tone(out, when, length * beat + 0.3, NOTE[name] * 2, 0.04, decay=4, sr=sr, wrap=True)

    # Gentle soft clip
    return [math.tanh(sample * 1.6) for sample in out], sr


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating audio into", OUT_DIR)
    save("click.wav", make_click())
    save("pop.wav", make_pop())
    save("error.wav", make_error())
    save("sell.wav", make_sell())
    save("success.wav", make_success())
    save("hatch.wav", make_hatch())
    save("alarm.wav", make_alarm())
    save("vacuum_loop.wav", make_vacuum_loop(), peak=0.7)
    music, music_rate = make_music_loop()
    save("music_loop.wav", music, sr=music_rate, peak=0.85)
    print("Done.")


if __name__ == "__main__":
    main()
