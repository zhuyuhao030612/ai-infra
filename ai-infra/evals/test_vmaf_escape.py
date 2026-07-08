"""Test VMAF path escaping for Windows."""
import tempfile
import os
import subprocess

# Check what the escaped path looks like
vmaf_log = tempfile.mktemp(suffix="_vmaf.json")
print(f"Original path: {vmaf_log!r}")

safe = vmaf_log.replace("\\", "/").replace(":", "\\:")
print(f"Escaped path: {safe!r}")

# Build filter string
filter_str = (
    f"[0:v]format=yuv420p,setpts=PTS-STARTPTS[main];"
    f"[1:v]format=yuv420p,setpts=PTS-STARTPTS[ref];"
    f"[main][ref]libvmaf="
    f"model=version=vmaf_v0.6.1:"
    f"log_path={safe}:"
    f"log_fmt=json:"
    f"n_threads=8"
)
print(f"Filter string:\n  {filter_str!r}\n")

# Generate a test video
test_video = os.path.join(tempfile.gettempdir(), "phs_vmaf_test_colon.mp4")
subprocess.run(
    ["ffmpeg", "-y",
     "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=10",
     "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
     "-an", "-frames:v", "10", test_video],
    capture_output=True, timeout=30, check=True,
)

# Try VMAF
r = subprocess.run(
    ["ffmpeg", "-y",
     "-i", test_video,
     "-i", test_video,
     "-filter_complex", filter_str,
     "-f", "null", "-"],
    capture_output=True, text=True, timeout=60,
)

print(f"Return code: {r.returncode}")
if r.returncode != 0:
    print(f"STDERR (last 1000):\n{r.stderr[-1000:]}")
else:
    print("SUCCESS!")
    print(f"STDERR (last 1000):\n{r.stderr[-1000:]}")

# Check if log file exists
if os.path.exists(vmaf_log):
    print(f"\nLog file exists!")
    with open(vmaf_log) as f:
        print(f.read()[:500])
    os.unlink(vmaf_log)

os.unlink(test_video)
