#!/usr/bin/env python3
"""Sssssssscroll recorder — calibration tool for detector templates.

Writes `templates/<name>.json` in the schema that `detector.py` consumes.

Usage:
    python recorder.py <name> <type> [--duration N] [--force]

    <name>      Sound name. Becomes the JSON filename and the `name` field.
    <type>      One of: template, band. (voiced is reserved for Wave 3.)
    --duration  For `band`, seconds of audio to capture (default 5).
                Ignored for `template` (capture is trigger-based).
    --force     Overwrite existing templates/<name>.json without prompting.

Template type (transient sounds like pop, tongue_click):
    Waits for a loud-enough RMS spike, then captures a 40-frame x 25-bin
    spectrogram CENTERED on the peak frame (fixes lead-edge bias in the
    legacy recorder). Normalizes so peak == 1.0.

Band type (sustained unvoiced sounds like shhh, hiss):
    Calibrates silence for 1s, then records `--duration` seconds while
    the user holds the sound. Computes mean power spectrum, identifies
    the widest contiguous bin run > 25% of peak-above-baseline. Refuses
    to write if SNR < 2.0.

Voiced type (sustained voiced sounds like mmm):
    Calibrates silence for 1s, then records `--duration` seconds while
    the user hums. Per frame: autocorrelation pitch peak in [80, 300] Hz,
    clarity, and low/high band-energy ratio. Refuses if fewer than 70% of
    frames are reliably voiced (clarity > 0.3). Calibration tunes pitch
    band (±40% of median) and ratio_min / clarity_min thresholds.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

import numpy as np

try:
    import pyaudio
except ImportError as e:
    print(f"[recorder] failed to import pyaudio: {e}", file=sys.stderr)
    print("[recorder] install with: pip install pyaudio numpy", file=sys.stderr)
    sys.exit(1)


# ---- Shared audio config (mirrors detector.py) -----------------------------
CHUNK = 512
RATE = 44100
N_BINS_FULL = CHUNK // 2 + 1  # 257
TEMPLATE_FRAMES = 40
TEMPLATE_BINS = 25
HAMMING = np.hamming(CHUNK)

# Template-trigger tuning
TRIGGER_RMS_FLOOR = 20.0           # absolute floor so silence can't trigger
TRIGGER_BASELINE_MULT = 5.0        # spike must be N× rolling baseline
BASELINE_WINDOW = 40               # frames of recent history for baseline
ROLLING_BUFFER_FRAMES = 2 * TEMPLATE_FRAMES  # 80 frames ≈ ~0.93 s
POST_TRIGGER_FRAMES = 20           # capture this many more frames after spike

# Band-recording tuning
SILENCE_CALIB_SECONDS = 1.0
BAND_PEAK_FRACTION = 0.25          # keep bins > 25% of peak-above-noise
BAND_GUARD_BINS = 3                # gap between main band and noise bands
MIN_BAND_SNR = 2.0                 # below this we refuse to save

# Detector defaults written into JSON (user can tune by editing)
TEMPLATE_DEFAULT_SENS = 6.0
TEMPLATE_DEFAULT_COOLDOWN = 0.15
TEMPLATE_DEFAULT_SHIFT = [-2, 5]

BAND_DEFAULT_SENS = 3.0
BAND_DEFAULT_HYSTERESIS = 0.8
BAND_DEFAULT_LOWPASS = 0.6

# Voiced-recording tuning
VOICED_PITCH_LO_HZ = 80.0
VOICED_PITCH_HI_HZ = 300.0
VOICED_LOW_BAND = [0, 30]    # bins (~0–2.6 kHz)
VOICED_HIGH_BAND = [60, 257] # bins (~5.2–22 kHz)
VOICED_CLARITY_GATE = 0.3    # frames below this are considered "not voiced"
VOICED_MIN_VOICED_FRACTION = 0.7
VOICED_PITCH_TOLERANCE = 0.4 # ±40 % of median pitch
VOICED_THRESHOLD_HEADROOM = 0.7  # ratio_min and clarity_min set to 0.7 * median
VOICED_DEFAULT_HYSTERESIS = 0.8


SUPPORTED_TYPES = {"template", "band", "voiced"}
FUTURE_TYPES: set = set()


# ---- Helpers ---------------------------------------------------------------
def bin_to_hz(bin_idx: int) -> float:
    """rfft bin index → approximate centre frequency in Hz.

    With CHUNK=512 the rfft length is 257; bin spacing is RATE/CHUNK = ~86 Hz.
    """
    return bin_idx * RATE / CHUNK


def compute_fft_power(chunk: np.ndarray) -> np.ndarray:
    fft_vals = np.fft.rfft(chunk * HAMMING)
    return np.abs(fft_vals) ** 2


def compute_rms(chunk: np.ndarray) -> float:
    return float(np.sqrt(np.mean(chunk * chunk))) * 1000.0


def open_stream(p: "pyaudio.PyAudio"):
    return p.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=RATE,
        input=True,
        frames_per_buffer=CHUNK,
    )


def read_chunk(stream) -> np.ndarray:
    raw = stream.read(CHUNK, exception_on_overflow=False)
    return np.frombuffer(raw, dtype=np.float32)


def confirm_overwrite(path: Path, force: bool) -> bool:
    if not path.exists() or force:
        return True
    ans = input(f"{path.name} already exists. Overwrite? [y/N]: ").strip().lower()
    return ans == "y"


def confirm_save(path: Path) -> bool:
    ans = input(f"save to {path}? [Y/n]: ").strip().lower()
    return ans in ("", "y", "yes")


def render_ascii_bars(values: list, width: int = 40) -> str:
    """One-line ASCII bar chart for a sequence of floats. Marks peak with *."""
    if not values:
        return ""
    arr = np.asarray(values, dtype=float)
    peak_idx = int(np.argmax(arr))
    vmax = float(np.max(arr)) or 1.0
    levels = " .:-=+*#%@"
    out = []
    for i, v in enumerate(arr):
        norm = max(0.0, min(1.0, v / vmax))
        ch = levels[int(norm * (len(levels) - 1))]
        if i == peak_idx:
            ch = "^"
        out.append(ch)
    return "".join(out)


# ---- JSON writers ----------------------------------------------------------
def write_template_json(
    name: str,
    data: list,
    out_dir: Path,
    sensitivity: float = TEMPLATE_DEFAULT_SENS,
    cooldown: float = TEMPLATE_DEFAULT_COOLDOWN,
    shift_range=None,
) -> Path:
    """Write a template-type config JSON. Returns the written path."""
    if shift_range is None:
        shift_range = TEMPLATE_DEFAULT_SHIFT
    expected = TEMPLATE_FRAMES * TEMPLATE_BINS
    if len(data) != expected:
        raise ValueError(
            f"template data length {len(data)} != frames*bins = {expected}"
        )
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "type": "template",
        "name": name,
        "frames": TEMPLATE_FRAMES,
        "bins": TEMPLATE_BINS,
        "sensitivity": sensitivity,
        "cooldown": cooldown,
        "shift_range": list(shift_range),
        "data": list(data),
    }
    path = out_dir / f"{name}.json"
    path.write_text(json.dumps(payload))
    return path


def write_voiced_json(
    name: str,
    pitch_hz: list,
    ratio_min: float,
    clarity_min: float,
    out_dir: Path,
    low_band=None,
    high_band=None,
    hysteresis: float = VOICED_DEFAULT_HYSTERESIS,
) -> Path:
    if low_band is None:
        low_band = list(VOICED_LOW_BAND)
    if high_band is None:
        high_band = list(VOICED_HIGH_BAND)
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "type": "voiced",
        "name": name,
        "pitch_hz": list(pitch_hz),
        "low_band": list(low_band),
        "high_band": list(high_band),
        "ratio_min": float(ratio_min),
        "clarity_min": float(clarity_min),
        "hysteresis": float(hysteresis),
    }
    path = out_dir / f"{name}.json"
    path.write_text(json.dumps(payload))
    return path


def write_band_json(
    name: str,
    main_band: list,
    noise_bands: list,
    out_dir: Path,
    sensitivity: float = BAND_DEFAULT_SENS,
    hysteresis: float = BAND_DEFAULT_HYSTERESIS,
    lowpass: float = BAND_DEFAULT_LOWPASS,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "type": "band",
        "name": name,
        "main_band": list(main_band),
        "noise_bands": [list(b) for b in noise_bands],
        "sensitivity": sensitivity,
        "hysteresis": hysteresis,
        "lowpass": lowpass,
    }
    path = out_dir / f"{name}.json"
    path.write_text(json.dumps(payload))
    return path


# ---- Template recorder -----------------------------------------------------
def record_template(name: str, out_dir: Path, force: bool) -> int:
    """Interactive template (transient) capture session."""
    out_path = out_dir / f"{name}.json"
    if not confirm_overwrite(out_path, force):
        print("[recorder] aborted by user")
        return 1

    print()
    print(f"  RECORDING TEMPLATE: {name}")
    print("  ----------------------------------------------------------")
    print("  Hold mic still. Wait ~2 s for the buffer to fill,")
    print(f"  then make a single clear '{name}' sound.")
    print("  Ctrl-C to abort.")
    print()

    p = pyaudio.PyAudio()
    try:
        try:
            stream = open_stream(p)
        except (IOError, OSError) as e:
            print(f"[recorder] no microphone available: {e}", file=sys.stderr)
            return 1

        try:
            captured = _capture_template_session(stream, name)
        finally:
            try:
                stream.stop_stream()
                stream.close()
            except Exception:
                pass
    finally:
        p.terminate()

    if captured is None:
        print("[recorder] capture aborted")
        return 1

    matrix, rms_series, peak_local_idx = captured
    peak_rms = float(rms_series[peak_local_idx])
    max_val = float(np.max(matrix))
    if max_val <= 0.0:
        print("[recorder] captured silence (peak power == 0); aborting")
        return 1
    norm = matrix / max_val

    print()
    print(f"  captured {TEMPLATE_FRAMES}x{TEMPLATE_BINS} spectrogram")
    print(f"  peak RMS = {peak_rms:.1f}, normalized max = {float(np.max(norm)):.3f}")
    print(f"  RMS shape (peak marked '^'):")
    print(f"  [{render_ascii_bars(rms_series)}]")
    print()

    while True:
        if confirm_save(out_path):
            written = write_template_json(name, norm.flatten().tolist(), out_dir)
            print(f"[recorder] wrote {written}")
            return 0
        ans = input("re-record (r), quit (q)? [r/Q]: ").strip().lower()
        if ans == "r":
            return record_template(name, out_dir, force=True)
        print("[recorder] not saving; exiting")
        return 1


def _capture_template_session(stream, name: str):
    """Drive the mic loop for a template capture. Returns (matrix, rms_series, peak_idx) or None."""
    fft_cols: list = []   # rolling list of length-25 spectrum slices
    rms_hist: list = []   # rolling list of frame RMS values (matches fft_cols)
    print("  buffering", end="", flush=True)
    buffer_warm_frames = ROLLING_BUFFER_FRAMES
    spike_frame = None
    frames_since_spike = 0
    frame_count = 0

    try:
        while True:
            data = read_chunk(stream)
            fft_power = compute_fft_power(data)
            col = fft_power[:TEMPLATE_BINS]
            rms = compute_rms(data)

            fft_cols.append(col)
            rms_hist.append(rms)
            if len(fft_cols) > ROLLING_BUFFER_FRAMES:
                fft_cols.pop(0)
                rms_hist.pop(0)

            frame_count += 1

            # Live feedback
            if frame_count <= buffer_warm_frames:
                if frame_count % 10 == 0:
                    print(".", end="", flush=True)
                if frame_count == buffer_warm_frames:
                    print()
                    print("  listening (make the sound now)")
                continue

            # Spike detection: baseline = median of recent history excluding tail
            if spike_frame is None:
                hist_slice = rms_hist[-BASELINE_WINDOW:-1] if len(rms_hist) > 1 else rms_hist
                if hist_slice:
                    baseline = float(np.median(hist_slice))
                else:
                    baseline = 0.0
                threshold = max(TRIGGER_RMS_FLOOR, TRIGGER_BASELINE_MULT * baseline)
                if rms > threshold:
                    spike_frame = len(rms_hist) - 1  # index of this frame in current buffer
                    print(f"  ! spike rms={rms:.1f} (baseline={baseline:.1f}, thresh={threshold:.1f})")
                else:
                    if frame_count % 20 == 0:
                        print(".", end="", flush=True)
                continue

            # Post-trigger: keep capturing frames so we can centre on the peak
            frames_since_spike += 1
            print("!", end="", flush=True)
            if frames_since_spike >= POST_TRIGGER_FRAMES:
                print()
                break

    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted")
        return None

    if spike_frame is None or len(fft_cols) < TEMPLATE_FRAMES:
        print("[recorder] no spike detected")
        return None

    cols_arr = np.asarray(fft_cols)            # (T, 25)
    rms_arr = np.asarray(rms_hist)             # (T,)
    peak_idx = int(np.argmax(rms_arr))

    # Capture FRAMES centred on peak: 20 before + peak + 19 after = 40
    pre = TEMPLATE_FRAMES // 2                  # 20
    post = TEMPLATE_FRAMES - pre - 1            # 19 (so total = 40)
    lo = peak_idx - pre
    hi = peak_idx + post + 1
    # Clamp if peak too close to edge
    if lo < 0:
        hi += -lo
        lo = 0
    if hi > len(cols_arr):
        lo -= hi - len(cols_arr)
        hi = len(cols_arr)
        if lo < 0:
            print("[recorder] not enough data around peak; aborting")
            return None

    matrix = cols_arr[lo:hi]
    rms_slice = rms_arr[lo:hi].tolist()
    peak_local_idx = peak_idx - lo
    return matrix, rms_slice, peak_local_idx


# ---- Band recorder ---------------------------------------------------------
def record_band(name: str, out_dir: Path, duration: float, force: bool) -> int:
    out_path = out_dir / f"{name}.json"
    if not confirm_overwrite(out_path, force):
        print("[recorder] aborted by user")
        return 1

    print()
    print(f"  RECORDING BAND: {name}")
    print("  ----------------------------------------------------------")
    print(f"  Make and HOLD a '{name}' sound for {duration:.0f} s.")
    print("  Calibrating silence first — stay quiet briefly.")
    print()

    p = pyaudio.PyAudio()
    try:
        try:
            stream = open_stream(p)
        except (IOError, OSError) as e:
            print(f"[recorder] no microphone available: {e}", file=sys.stderr)
            return 1

        try:
            result = _capture_band_session(stream, name, duration)
        finally:
            try:
                stream.stop_stream()
                stream.close()
            except Exception:
                pass
    finally:
        p.terminate()

    if result is None:
        print("[recorder] capture aborted")
        return 1

    signal_mean, baseline_mean, capture_rms = result

    # Excess power above baseline
    excess = np.maximum(signal_mean - baseline_mean, 0.0)
    # Skip DC + first couple of bins (mic rumble)
    excess[:3] = 0.0
    if float(np.max(excess)) <= 0.0:
        print("[recorder] no signal above noise floor; aborting")
        return 1

    main_lo, main_hi = _widest_run_above(excess, BAND_PEAK_FRACTION * float(np.max(excess)))
    if main_hi <= main_lo:
        print("[recorder] could not identify a main band; aborting")
        return 1

    # Build noise bands as the complement, with a guard gap on each side.
    noise_bands = _build_noise_bands(main_lo, main_hi, N_BINS_FULL, BAND_GUARD_BINS)

    main_power = float(np.mean(signal_mean[main_lo:main_hi]))
    if noise_bands:
        noise_powers = [float(np.mean(signal_mean[lo:hi])) for lo, hi in noise_bands]
        noise_power = sum(noise_powers) / len(noise_powers)
    else:
        noise_power = 0.0
    snr = main_power / (noise_power + 1e-9)

    lo_hz = bin_to_hz(main_lo)
    hi_hz = bin_to_hz(main_hi)

    print()
    print(f"  main_band = [{main_lo}, {main_hi}]  (~{lo_hz:.0f} Hz to {hi_hz:.0f} Hz)")
    print(f"  noise_bands = {noise_bands}")
    print(f"  SNR (main / noise mean power) = {snr:.2f}")
    print(f"  capture mean RMS = {capture_rms:.1f}")
    print()

    if snr < MIN_BAND_SNR:
        print(
            f"[recorder] signal too weak relative to noise (SNR={snr:.2f} < {MIN_BAND_SNR}). "
            "Please re-record in a quieter room or hold the sound more firmly."
        )
        return 1

    while True:
        if confirm_save(out_path):
            written = write_band_json(name, [main_lo, main_hi], noise_bands, out_dir)
            print(f"[recorder] wrote {written}")
            return 0
        ans = input("re-record (r), quit (q)? [r/Q]: ").strip().lower()
        if ans == "r":
            return record_band(name, out_dir, duration, force=True)
        print("[recorder] not saving; exiting")
        return 1


def _capture_band_session(stream, name: str, duration: float):
    """Drive the mic loop for a band capture. Returns (signal_mean, baseline_mean, rms_mean) or None."""
    # 1) Silence calibration
    print("  calibrating silence...", flush=True)
    silence_frames = max(1, int(round(SILENCE_CALIB_SECONDS * RATE / CHUNK)))
    baseline_spectra = []
    t_last_print = time.time()
    try:
        for i in range(silence_frames):
            data = read_chunk(stream)
            baseline_spectra.append(compute_fft_power(data))
            now = time.time()
            if now - t_last_print >= 0.5:
                print("  ...", flush=True)
                t_last_print = now
        baseline_mean = np.mean(np.asarray(baseline_spectra), axis=0)
        print(f"  silence baseline mean RMS-ish = {float(np.sqrt(np.mean(baseline_mean))):.3f}")
    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted during silence calibration")
        return None

    # 2) Countdown then capture
    print(f"  starting capture in 2...", flush=True)
    time.sleep(1.0)
    print(f"  1...", flush=True)
    time.sleep(1.0)
    print(f"  GO — hold the '{name}' sound now")

    capture_frames_total = max(1, int(round(duration * RATE / CHUNK)))
    signal_spectra = []
    rms_values = []
    sec_print_due = time.time() + 1.0
    sec_counter = 1
    try:
        for i in range(capture_frames_total):
            data = read_chunk(stream)
            fft_power = compute_fft_power(data)
            signal_spectra.append(fft_power)
            rms_values.append(compute_rms(data))

            now = time.time()
            if now >= sec_print_due:
                # Per-second progress: rough SNR estimate over recent frames
                recent = np.mean(np.asarray(signal_spectra[-int(RATE / CHUNK):]), axis=0)
                excess_now = np.maximum(recent - baseline_mean, 0.0)
                excess_now[:3] = 0.0
                main_idx = int(np.argmax(excess_now)) if np.max(excess_now) > 0 else 0
                rough_snr = float(recent[main_idx] / (np.mean(baseline_mean) + 1e-9))
                print(
                    f"  [{sec_counter:>2}s] rms={rms_values[-1]:6.1f}  peak_bin={main_idx:3d}  "
                    f"rough_snr={rough_snr:6.1f}",
                    flush=True,
                )
                sec_counter += 1
                sec_print_due = now + 1.0
    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted during capture")
        return None

    if not signal_spectra:
        return None
    signal_mean = np.mean(np.asarray(signal_spectra), axis=0)
    capture_rms = float(np.mean(rms_values))
    return signal_mean, baseline_mean, capture_rms


# ---- Voiced recorder -------------------------------------------------------
def record_voiced(name: str, out_dir: Path, duration: float, force: bool) -> int:
    out_path = out_dir / f"{name}.json"
    if not confirm_overwrite(out_path, force):
        print("[recorder] aborted by user")
        return 1

    print()
    print(f"  RECORDING VOICED: {name}")
    print("  ----------------------------------------------------------")
    print(f"  Hum and hold a '{name}' sound (mouth closed for mmm)")
    print(f"  for {duration:.0f} s. Calibrating silence first — stay quiet briefly.")
    print()
    print(f"  Starting in 2...", flush=True)
    time.sleep(1.0)
    print(f"  1...", flush=True)
    time.sleep(1.0)

    p = pyaudio.PyAudio()
    try:
        try:
            stream = open_stream(p)
        except (IOError, OSError) as e:
            print(f"[recorder] no microphone available: {e}", file=sys.stderr)
            return 1

        try:
            result = _capture_voiced_session(stream, name, duration)
        finally:
            try:
                stream.stop_stream()
                stream.close()
            except Exception:
                pass
    finally:
        p.terminate()

    if result is None:
        print("[recorder] capture aborted")
        return 1

    frames = result  # list of dicts: pitch_hz, clarity, low_e, high_e
    if not frames:
        print("[recorder] no audio captured; aborting")
        return 1

    total_frames = len(frames)
    voiced = [f for f in frames if f["clarity"] > VOICED_CLARITY_GATE]
    voiced_frac = len(voiced) / total_frames

    if voiced_frac < VOICED_MIN_VOICED_FRACTION:
        print(
            f"[recorder] couldn't reliably detect voicing "
            f"({voiced_frac * 100:.0f}% of {total_frames} frames passed clarity>{VOICED_CLARITY_GATE}, "
            f"need >= {VOICED_MIN_VOICED_FRACTION * 100:.0f}%). Please re-record."
        )
        return 1

    pitches = np.asarray([f["pitch_hz"] for f in voiced])
    clarities = np.asarray([f["clarity"] for f in voiced])
    ratios = np.asarray([f["low_e"] / (f["high_e"] + 1e-9) for f in voiced])

    med_pitch = float(np.median(pitches))
    med_clarity = float(np.median(clarities))
    med_ratio = float(np.median(ratios))

    # Clamp pitch range to detector limits used by VoicedDetector at CHUNK=512.
    pitch_lo = max(VOICED_PITCH_LO_HZ, med_pitch * (1.0 - VOICED_PITCH_TOLERANCE))
    pitch_hi = min(VOICED_PITCH_HI_HZ, med_pitch * (1.0 + VOICED_PITCH_TOLERANCE))
    if pitch_hi <= pitch_lo:
        # Degenerate (median outside [80,300]) — fall back to full range.
        pitch_lo, pitch_hi = VOICED_PITCH_LO_HZ, VOICED_PITCH_HI_HZ

    ratio_min = VOICED_THRESHOLD_HEADROOM * med_ratio
    clarity_min = VOICED_THRESHOLD_HEADROOM * med_clarity

    print()
    print(f"  voiced frames: {len(voiced)}/{total_frames} ({voiced_frac * 100:.0f}%)")
    print(f"  median pitch ~{med_pitch:.0f} Hz, clarity ~{med_clarity:.3f}, low/high ratio ~{med_ratio:.2f}")
    print(
        f"  Will save pitch_hz=[{pitch_lo:.0f}, {pitch_hi:.0f}], "
        f"clarity_min={clarity_min:.3f}, ratio_min={ratio_min:.2f}"
    )
    print()

    while True:
        if confirm_save(out_path):
            written = write_voiced_json(
                name,
                pitch_hz=[float(pitch_lo), float(pitch_hi)],
                ratio_min=ratio_min,
                clarity_min=clarity_min,
                out_dir=out_dir,
            )
            print(f"[recorder] wrote {written}")
            return 0
        ans = input("re-record (r), quit (q)? [r/Q]: ").strip().lower()
        if ans == "r":
            return record_voiced(name, out_dir, duration, force=True)
        print("[recorder] not saving; exiting")
        return 1


def _capture_voiced_session(stream, name: str, duration: float):
    """Drive the mic loop for a voiced capture.

    Returns list[dict{pitch_hz, clarity, low_e, high_e}] or None on abort.
    Skips a 1 s silence baseline first (matches band subflow).
    """
    # 1) Silence baseline (collected but not used to set thresholds — voiced
    #    discrimination is autocorrelation-based, not power-difference-based).
    print("  calibrating silence...", flush=True)
    silence_frames = max(1, int(round(SILENCE_CALIB_SECONDS * RATE / CHUNK)))
    try:
        for _ in range(silence_frames):
            read_chunk(stream)
    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted during silence calibration")
        return None

    print(f"  GO — hold the '{name}' sound now")

    # Default pitch search range for calibration (full detector-supported range).
    lag_lo = max(1, int(RATE / VOICED_PITCH_HI_HZ))
    lag_hi = min(CHUNK - 1, int(RATE / VOICED_PITCH_LO_HZ))

    capture_frames_total = max(1, int(round(duration * RATE / CHUNK)))
    frames_out: list = []
    sec_print_due = time.time() + 1.0
    sec_counter = 1
    sec_buffer: list = []  # pitches captured this second (for live feedback)
    sec_clar_buffer: list = []

    try:
        for _ in range(capture_frames_total):
            data = read_chunk(stream)
            fft_power = compute_fft_power(data)

            autocorr = np.fft.irfft(fft_power, n=CHUNK)
            r0 = float(autocorr[0])
            if r0 <= 1e-12:
                pitch_hz = 0.0
                clarity = 0.0
            else:
                window = autocorr[lag_lo:lag_hi]
                if len(window) == 0:
                    pitch_hz = 0.0
                    clarity = 0.0
                else:
                    peak_lag = int(np.argmax(window)) + lag_lo
                    peak_val = float(autocorr[peak_lag])
                    clarity = peak_val / r0
                    pitch_hz = float(RATE) / float(peak_lag) if peak_lag > 0 else 0.0

            low_e = float(np.mean(fft_power[VOICED_LOW_BAND[0]:VOICED_LOW_BAND[1]]))
            high_e = float(np.mean(fft_power[VOICED_HIGH_BAND[0]:VOICED_HIGH_BAND[1]]))

            frames_out.append({
                "pitch_hz": pitch_hz,
                "clarity": clarity,
                "low_e": low_e,
                "high_e": high_e,
            })
            sec_buffer.append(pitch_hz)
            sec_clar_buffer.append(clarity)

            now = time.time()
            if now >= sec_print_due:
                med_p = float(np.median(sec_buffer)) if sec_buffer else 0.0
                med_c = float(np.median(sec_clar_buffer)) if sec_clar_buffer else 0.0
                print(
                    f"  [{sec_counter:>2}s] pitch~{med_p:6.1f} Hz  clarity~{med_c:5.3f}",
                    flush=True,
                )
                sec_counter += 1
                sec_print_due = now + 1.0
                sec_buffer = []
                sec_clar_buffer = []
    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted during capture")
        return None

    return frames_out


def _widest_run_above(arr: np.ndarray, threshold: float):
    """Return (lo, hi) of the longest contiguous run of indices where arr > threshold.

    `hi` is exclusive (Python slice convention). Returns (0, 0) if no run exists.
    """
    n = len(arr)
    best_lo = best_hi = 0
    best_len = 0
    i = 0
    while i < n:
        if arr[i] > threshold:
            j = i
            while j < n and arr[j] > threshold:
                j += 1
            length = j - i
            if length > best_len:
                best_len = length
                best_lo = i
                best_hi = j
            i = j
        else:
            i += 1
    return best_lo, best_hi


def _build_noise_bands(main_lo: int, main_hi: int, n_bins: int, guard: int):
    """Return list of [lo, hi] noise bands surrounding the main band, with a guard gap."""
    bands = []
    left_lo = 3  # skip DC
    left_hi = max(left_lo, main_lo - guard)
    if left_hi - left_lo > 0:
        bands.append([int(left_lo), int(left_hi)])
    right_lo = min(n_bins, main_hi + guard)
    right_hi = n_bins
    if right_hi - right_lo > 0:
        bands.append([int(right_lo), int(right_hi)])
    return bands


# ---- CLI -------------------------------------------------------------------
def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="recorder.py",
        description="Calibrate a Sssssssscroll sound template (template or band).",
    )
    parser.add_argument(
        "name",
        help="Sound name (e.g. shhh, tongue_click). Becomes templates/<name>.json.",
    )
    parser.add_argument(
        "type",
        help="Detector type: template (transient), band (sustained unvoiced), or voiced (sustained voiced).",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=5.0,
        help="For band/voiced types: seconds to record (default 5). Ignored for template.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing templates/<name>.json without prompting.",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    name = args.name.strip()
    if not name or "/" in name or os.sep in name:
        print(f"[recorder] invalid name: {name!r}", file=sys.stderr)
        return 2

    ttype = args.type.strip().lower()
    if ttype in FUTURE_TYPES:
        print(
            f"[recorder] '{ttype}' type not yet supported in this wave (planned for Wave 3).",
            file=sys.stderr,
        )
        return 2
    if ttype not in SUPPORTED_TYPES:
        print(
            f"[recorder] unknown type {ttype!r}; expected one of {sorted(SUPPORTED_TYPES)}.",
            file=sys.stderr,
        )
        return 2

    here = Path(__file__).resolve().parent
    out_dir = here / "templates"

    try:
        if ttype == "template":
            return record_template(name, out_dir, force=args.force)
        if ttype == "voiced":
            return record_voiced(name, out_dir, duration=args.duration, force=args.force)
        return record_band(name, out_dir, duration=args.duration, force=args.force)
    except KeyboardInterrupt:
        print()
        print("[recorder] interrupted")
        return 0


if __name__ == "__main__":
    sys.exit(main())
