import sys
import time

import numpy as np
import pyaudio

# --- CONFIG ---
CHUNK = 512
RATE = 44100
# Width of the template (40 time steps)
TEMPLATE_WIDTH = 40
# Height of the template (25 frequency bins)
TEMPLATE_HEIGHT = 25


def main():
    p = pyaudio.PyAudio()
    stream = p.open(
        format=pyaudio.paFloat32,
        channels=1,
        rate=RATE,
        input=True,
        frames_per_buffer=CHUNK,
    )

    print("\n🔴 RECORDER READY.")
    print("   1. Sit in a quiet room.")
    print("   2. Make your 'Lip Pop' sound CLEARLY and LOUDLY.")
    print("   3. The script will auto-capture and print your template.\n")

    # We keep a rolling buffer of the last 40 frames
    # So when you pop, we have the history leading up to it
    history_buffer = []

    try:
        while True:
            raw = stream.read(CHUNK, exception_on_overflow=False)
            data = np.frombuffer(raw, dtype=np.float32)

            # 1. Compute FFT for this frame
            window = np.hamming(len(data))
            fft_vals = np.fft.rfft(data * window)
            fft_power = np.abs(fft_vals) ** 2

            # 2. Take only the first 25 freq bins (matches our detector)
            col = fft_power[:TEMPLATE_HEIGHT]

            # 3. Calculate Loudness (RMS)
            rms = np.sqrt(np.mean(data**2)) * 1000

            # 4. Add to history
            history_buffer.append(col)
            if len(history_buffer) > TEMPLATE_WIDTH:
                history_buffer.pop(0)

            # 5. TRIGGER: If loud pop detected
            if rms > 20:  # Threshold for recording
                print(f"💥 CAPTURED! (Loudness: {int(rms)})")

                # Wait a tiny bit to ensure we captured the tail of the sound
                time.sleep(0.1)

                # Normalize the buffer (Make the loudest point 1.0)
                # This ensures volume differences don't break the match
                arr = np.array(history_buffer)  # Shape: (40, 25)
                max_val = np.max(arr)
                if max_val == 0:
                    max_val = 1
                norm_arr = arr / max_val

                # Flatten to 1D list for easy copy-pasting
                flat_list = norm_arr.flatten().tolist()

                print("\n⬇️ COPY THE CODE BLOCK BELOW ⬇️\n")
                print(f"RAW_POP_TEMPLATE = {flat_list}")
                print(
                    "\n⬆️ PASTE THIS INTO noises.py (Replace the old RAW_POP_TEMPLATE) ⬆️"
                )
                break

    except KeyboardInterrupt:
        pass
    finally:
        stream.stop_stream()
        p.terminate()


if __name__ == "__main__":
    main()
