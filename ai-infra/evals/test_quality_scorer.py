"""QualityScorer 功能测试。"""
import subprocess
import tempfile
import os
import sys
import time

# Ensure quality_scorer is importable
sys.path.insert(0, r"D:\PHS\Prism Studio\engines")

# Generate test video
test_video = os.path.join(tempfile.gettempdir(), "phs_qscore_test2.mp4")
gen = subprocess.run(
    ["ffmpeg", "-y",
     "-f", "lavfi", "-i", "testsrc=duration=3:size=320x240:rate=30",
     "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
     "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
     "-c:a", "aac", "-shortest", test_video],
    capture_output=True, text=True, timeout=30,
)
assert gen.returncode == 0, f"Generate failed: {gen.stderr[:300]}"
print(f"Test video: {test_video} ({os.path.getsize(test_video)} bytes)")

from quality_scorer import QualityScorer

scorer = QualityScorer(gpu=True)
print(f"GPU: {scorer.gpu}")
print()

# Full score (no-reference)
result = scorer.score_video(test_video)
print("=== NO-REFERENCE SCORE ===")
for k, v in result.items():
    if k != "info":
        print(f"  {k}: {v}")
print()

# Quick score
quick = scorer.quick_score(test_video)
print(f"Quick score: {quick}")

# Acceptable check
print(f"Acceptable: {scorer.is_acceptable(result)}")

# Reference mode (self as reference)
result_ref = scorer.score_video(test_video, reference=test_video)
print()
print("=== REFERENCE MODE (self) ===")
for k, v in result_ref.items():
    if k != "info":
        print(f"  {k}: {v}")
print()

# Compare renditions (same video -> tie)
ab = scorer.compare_renditions(test_video, test_video)
print(f"A/B winner: {ab['winner']}")
print()

# Cache hit test
t0 = time.time()
cached = scorer.score_video(test_video)
cached_ms = int((time.time() - t0) * 1000)
print(f"Cached call: {cached_ms}ms (expected < 50ms)")
assert cached["overall"] == result["overall"], "Cache mismatch"

# Clear cache
cleared = scorer.clear_cache()
print(f"Cache cleared: {cleared} entries")

# Cleanup
os.unlink(test_video)
print()
print("ALL TESTS PASSED")
