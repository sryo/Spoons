#!/usr/bin/env python3
"""Sssssssscroll detector — reads mic, emits sound events on stdout.

Event protocol (one event per newline, two tokens):
    start <name>     # sustained sound began
    stop  <name>     # sustained sound ended
    trigger <name>   # transient sound fired

Must be invoked with `python -u detector.py` for unbuffered stdout. We also
call sys.stdout.reconfigure(line_buffering=True) below as a belt-and-suspenders
guard — without unbuffered output the event stream batches into multi-second
bursts when piped to hs.task.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import pyaudio

# Belt-and-suspenders: -u flag should already make stdout unbuffered, but
# line_buffering=True guarantees flush on each newline if -u is forgotten.
sys.stdout.reconfigure(line_buffering=True)

# ---- Audio config ----------------------------------------------------------
CHUNK = 512
RATE = 44100
N_BINS = CHUNK // 2 + 1  # rfft bin count = 257

# Min-dwell + switch-margin for sustained-sound discrimination
MIN_DWELL_S = 0.08
SWITCH_MARGIN = 1.3

# Transient gate
RMS_FLOOR = 1.0


# ---- Base detector ---------------------------------------------------------
class Detector:
    name: str = ""
    kind: str = ""  # "sustained" | "transient"

    def process(self, fft_power, audio_chunk, rms, now):
        """Return (active, score)."""
        raise NotImplementedError


# ---- BandDetector (ported from TssDetector in noises.py:1059) --------------
class BandDetector(Detector):
    """Sustained unvoiced sound: SNR of a main FFT band vs surrounding noise."""

    kind = "sustained"

    def __init__(self, cfg: dict):
        self.name = cfg["name"]
        self.main_lo, self.main_hi = cfg["main_band"]
        self.noise_bands = [tuple(b) for b in cfg["noise_bands"]]
        self.sensitivity = float(cfg["sensitivity"])
        self.hysteresis = float(cfg.get("hysteresis", 0.8))
        self.lowpass = float(cfg.get("lowpass", 0.6))
        self.spectrum_buffer = np.zeros(N_BINS)
        self.triggered = False

    def process(self, fft_power, audio_chunk, rms, now):
        # Low-pass smoothing on the spectrum
        self.spectrum_buffer = (
            self.spectrum_buffer * (1.0 - self.lowpass) + fft_power * self.lowpass
        )
        main = np.mean(self.spectrum_buffer[self.main_lo : self.main_hi])
        noise_means = [
            np.mean(self.spectrum_buffer[lo:hi]) for lo, hi in self.noise_bands
        ]
        noise = (sum(noise_means) / len(noise_means)) + 1e-5
        matchiness = main / noise

        if not self.triggered:
            if matchiness > self.sensitivity:
                self.triggered = True
                return True, float(matchiness)
            return False, float(matchiness)
        # already triggered — apply hysteresis to release
        if matchiness < self.sensitivity * self.hysteresis:
            self.triggered = False
            return False, float(matchiness)
        return True, float(matchiness)


# ---- TemplateDetector (ported from PopDetector in noises.py:1086) ----------
class TemplateDetector(Detector):
    """Transient sound: rolling FFT spectrogram vs normalized template."""

    kind = "transient"

    def __init__(self, cfg: dict):
        self.name = cfg["name"]
        self.frames = int(cfg["frames"])
        self.bins = int(cfg["bins"])
        data = cfg["data"]
        expected = self.frames * self.bins
        if len(data) != expected:
            raise ValueError(
                f"{self.name}: template data length {len(data)} != "
                f"frames*bins = {expected}"
            )
        self.template = np.array(data, dtype=np.float64).reshape(self.frames, self.bins)
        self.sensitivity = float(cfg["sensitivity"])
        self.cooldown = float(cfg.get("cooldown", 0.15))
        lo, hi = cfg.get("shift_range", [-2, 5])
        self.shift_lo, self.shift_hi = int(lo), int(hi)
        self.buffer = np.zeros((self.frames, self.bins))
        self.last_trigger_time = 0.0

    def process(self, fft_power, audio_chunk, rms, now):
        if now - self.last_trigger_time < self.cooldown:
            return False, 999.0

        # Roll buffer up, drop in the new frame's first `bins` FFT values
        new_col = fft_power[: self.bins]
        self.buffer = np.roll(self.buffer, -1, axis=0)
        self.buffer[-1] = new_col

        max_val = np.max(self.buffer)
        if max_val < 1.0:
            return False, 999.0  # silence

        min_diff = 99999.0
        for shift in range(self.shift_lo, self.shift_hi):
            t_start, t_end = max(0, -shift), min(self.bins, self.bins - shift)
            b_start, b_end = max(0, shift), min(self.bins, self.bins + shift)
            t_slice = self.template[:, t_start:t_end]
            b_slice = self.buffer[:, b_start:b_end] / max_val
            diff = np.sum(np.abs(t_slice - b_slice))
            if diff < min_diff:
                min_diff = float(diff)

        if min_diff < self.sensitivity:
            self.last_trigger_time = now
            return True, min_diff
        return False, min_diff


# ---- VoicedDetector --------------------------------------------------------
class VoicedDetector(Detector):
    """Sustained voiced sound (e.g. mmm): periodic waveform → autocorrelation
    peak in a pitch lag range, plus a low/high band-energy ratio gate.

    JSON config:
        {"type":"voiced","name":"mmm",
         "pitch_hz":[80,300],
         "low_band":[0,30], "high_band":[60,257],
         "ratio_min":5.0,
         "clarity_min":0.5,
         "hysteresis":0.8}
    """

    kind = "sustained"

    def __init__(self, cfg: dict):
        self.name = cfg["name"]

        pitch_lo_hz, pitch_hi_hz = cfg["pitch_hz"]
        if pitch_hi_hz <= pitch_lo_hz or pitch_lo_hz <= 0:
            raise ValueError(
                f"{self.name}: invalid pitch_hz {cfg['pitch_hz']!r} (need lo < hi, both > 0)"
            )
        # Lag in samples = RATE / freq. Higher freq → shorter lag.
        lag_lo = int(RATE / pitch_hi_hz)
        lag_hi = int(RATE / pitch_lo_hz)
        # Clamp to valid autocorr range. autocorr from irfft(n=CHUNK) has length CHUNK.
        if lag_lo < 1:
            lag_lo = 1
        if lag_hi >= CHUNK:
            lag_hi = CHUNK - 1
        if lag_hi <= lag_lo:
            raise ValueError(
                f"{self.name}: pitch_hz {cfg['pitch_hz']!r} maps to empty lag "
                f"range [{lag_lo}, {lag_hi}] at CHUNK={CHUNK}"
            )
        self.lag_lo = lag_lo
        self.lag_hi = lag_hi

        self.low_lo, self.low_hi = cfg.get("low_band", [0, 30])
        self.high_lo, self.high_hi = cfg.get("high_band", [60, N_BINS])
        self.ratio_min = float(cfg["ratio_min"])
        self.clarity_min = float(cfg["clarity_min"])
        self.hysteresis = float(cfg.get("hysteresis", 0.8))
        self.rms_floor = float(cfg.get("rms_floor", 1.0))
        self.triggered = False

    def process(self, fft_power, audio_chunk, rms, now):
        if rms < self.rms_floor:
            if self.triggered:
                self.triggered = False
            return False, 0.0

        # Wiener-Khinchin: autocorr = IFFT of power spectrum.
        autocorr = np.fft.irfft(fft_power, n=CHUNK)
        r0 = float(autocorr[0])
        if r0 <= 1e-12:
            if self.triggered:
                self.triggered = False
            return False, 0.0

        peak = float(np.max(autocorr[self.lag_lo : self.lag_hi]))
        clarity = peak / r0

        low_mean = float(np.mean(fft_power[self.low_lo : self.low_hi]))
        high_mean = float(np.mean(fft_power[self.high_lo : self.high_hi])) + 1e-9
        ratio = low_mean / high_mean

        score = float(clarity * np.log1p(ratio))

        if not self.triggered:
            if clarity > self.clarity_min and ratio > self.ratio_min:
                self.triggered = True
                return True, score
            return False, score
        # Already triggered — hysteresis on both thresholds for release.
        if (
            clarity < self.clarity_min * self.hysteresis
            or ratio < self.ratio_min * self.hysteresis
        ):
            self.triggered = False
            return False, score
        return True, score


# ---- Detector loading ------------------------------------------------------
TYPE_REGISTRY = {
    "band": BandDetector,
    "template": TemplateDetector,
    "voiced": VoicedDetector,
}


def load_detectors(templates_dir: Path):
    sustained, transient = [], []
    if not templates_dir.is_dir():
        print(f"[detector] no templates dir at {templates_dir}", file=sys.stderr)
        return sustained, transient
    for path in sorted(templates_dir.glob("*.json")):
        try:
            cfg = json.loads(path.read_text())
        except Exception as e:
            print(f"[detector] bad json {path.name}: {e}", file=sys.stderr)
            continue
        ttype = cfg.get("type")
        cls = TYPE_REGISTRY.get(ttype)
        if not cls:
            print(f"[detector] unknown type {ttype!r} in {path.name}", file=sys.stderr)
            continue
        try:
            det = cls(cfg)
        except Exception as e:
            print(f"[detector] failed to build {path.name}: {e}", file=sys.stderr)
            continue
        (sustained if det.kind == "sustained" else transient).append(det)
        print(f"[detector] loaded {det.kind} {det.name} from {path.name}", file=sys.stderr)
    return sustained, transient


# ---- Main loop -------------------------------------------------------------
def main():
    here = Path(__file__).resolve().parent
    sustained, transient = load_detectors(here / "templates")
    if not sustained and not transient:
        print("[detector] no detectors loaded, exiting", file=sys.stderr)
        sys.exit(1)

    p = pyaudio.PyAudio()
    try:
        stream = p.open(
            format=pyaudio.paFloat32,
            channels=1,
            rate=RATE,
            input=True,
            frames_per_buffer=CHUNK,
        )
    except Exception as e:
        print(f"[detector] mic open failed: {e}", file=sys.stderr)
        sys.exit(1)

    window = np.hamming(CHUNK)

    active_sustained = None  # name of currently active sustained sound, or None
    active_score = 0.0
    active_since = 0.0

    try:
        while True:
            raw = stream.read(CHUNK, exception_on_overflow=False)
            data = np.frombuffer(raw, dtype=np.float32)
            fft_vals = np.fft.rfft(data * window)
            fft_power = np.abs(fft_vals) ** 2
            rms = float(np.sqrt(np.mean(data * data))) * 1000.0  # scaled
            now = time.time()

            # 1) Evaluate every sustained detector this frame.
            results = []
            for det in sustained:
                active, score = det.process(fft_power, data, rms, now)
                if active:
                    results.append((det.name, score))

            # Pick winner = highest score
            if results:
                results.sort(key=lambda t: t[1], reverse=True)
                winner_name, winner_score = results[0]
            else:
                winner_name, winner_score = None, 0.0

            # 2) Apply discrimination rules + emit transitions.
            if active_sustained is None and winner_name is not None:
                # None -> A
                print(f"start {winner_name}")
                active_sustained = winner_name
                active_score = winner_score
                active_since = now
            elif active_sustained is not None and winner_name is None:
                # A -> None
                print(f"stop {active_sustained}")
                active_sustained = None
                active_score = 0.0
                active_since = 0.0
            elif active_sustained is not None and winner_name is not None:
                if winner_name == active_sustained:
                    active_score = winner_score
                else:
                    # A -> B: only after min-dwell AND with switch margin
                    if (
                        now - active_since >= MIN_DWELL_S
                        and winner_score > active_score * SWITCH_MARGIN
                    ):
                        print(f"stop {active_sustained}")
                        print(f"start {winner_name}")
                        active_sustained = winner_name
                        active_score = winner_score
                        active_since = now

            # 3) Transients only when no sustained active, and only above RMS floor.
            if active_sustained is None and rms >= RMS_FLOOR:
                for det in transient:
                    active, _ = det.process(fft_power, data, rms, now)
                    if active:
                        print(f"trigger {det.name}")

    except KeyboardInterrupt:
        pass
    finally:
        try:
            stream.stop_stream()
            stream.close()
        except Exception:
            pass
        p.terminate()
        if active_sustained:
            print(f"stop {active_sustained}")


if __name__ == "__main__":
    main()
