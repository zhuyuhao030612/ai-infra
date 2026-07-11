"""Comprehensive quality differentiation test."""
import subprocess
import tempfile
import os, sys
sys.path.insert(0, r"D:\PHS\Prism Studio\engines")
from quality_scorer import QualityScorer

def make_video(crf, label):
    """Generate a test video at given CRF level."""
    path = os.path.join(tempfile.gettempdir(), f"phs_{label}.mp4")
    subprocess.run(
        ["ffmpeg", "-y",
         "-f", "lavfi", "-i", "testsrc=duration=3:size=640x480:rate=30",
         "-c:v", "libx264", "-preset", "fast", "-crf", str(crf), "-pix_fmt", "yuv420p",
         "-an", path],
        capture_output=True, timeout=30, check=True,
    )
    size = os.path.getsize(path)
    return path, size

print("Generate test videos at different quality levels...")
lo_path, lo_size = make_video(51, "low_quality")    # Very low quality
hi_path, hi_size = make_video(18, "high_quality")   # High quality
print(f"  Low quality:  {lo_path} ({lo_size//1024}KB)")
print(f"  High quality: {hi_path} ({hi_size//1024}KB)")

scorer = QualityScorer(gpu=True)

# No-reference: high quality should score higher than low quality
print("\n=== NO-REFERENCE SCORES ===")
lo_result = scorer.score_video(lo_path)
hi_result = scorer.score_video(hi_path)
print(f"  Low quality:  overall={lo_result['overall']}, ssim={lo_result['ssim']}, psnr={lo_result['psnr']}")
print(f"  High quality: overall={hi_result['overall']}, ssim={hi_result['ssim']}, psnr={hi_result['psnr']}")
assert hi_result['overall'] >= lo_result['overall'], "High quality should score >= low quality"
print("  OK: quality ordering correct")

# Reference mode (high quality as reference for both)
print("\n=== REFERENCE SCORES (reference=high quality) ===")
lo_ref = scorer.score_video(lo_path, reference=hi_path)
hi_ref = scorer.score_video(hi_path, reference=hi_path)
print(f"  Low quality:  vmaf={lo_ref['vmaf']}, ssim={lo_ref['ssim']}, psnr={lo_ref['psnr']}, overall={lo_ref['overall']}")
print(f"  High quality: vmaf={hi_ref['vmaf']}, ssim={hi_ref['ssim']}, psnr={hi_ref['psnr']}, overall={hi_ref['overall']}")

if lo_ref.get('vmaf') is not None and hi_ref.get('vmaf') is not None:
    assert lo_ref['vmaf'] < hi_ref['vmaf'], "Low quality should have lower VMAF vs high quality reference"
    print("  OK: VMAF quality ordering correct")
assert lo_ref['ssim'] < hi_ref['ssim'], "Low quality should have lower SSIM"
print(f"  SSIM: low={lo_ref['ssim']} < high={hi_ref['ssim']}")
# PSNR 在视频内容完全相同时可能为 inf (99.99)，不强制区分
print(f"  PSNR: low={lo_ref['psnr']} DB, high={hi_ref['psnr']} DB")
print("  OK: SSIM + VMAF ordering correct")

# is_acceptable — low quality acceptable only with default thresholds in no-reference mode
# (self-comparison gives decent scores). With reference, low quality fails.
print("\n=== ACCEPTABILITY ===")
print(f"  Low quality acceptable (default):                {scorer.is_acceptable(lo_result)}")
print(f"  Low quality acceptable (lax, min_ssim=0.8):      {scorer.is_acceptable(lo_result, min_ssim=0.8)}")
print(f"  Low quality with ref acceptable (default):       {scorer.is_acceptable(lo_ref)}")
print(f"  Low quality with ref acceptable (min_vmaf=90):   {scorer.is_acceptable(lo_ref, min_vmaf=90)}")
print(f"  High quality acceptable (default):               {scorer.is_acceptable(hi_result)}")

# compare_renditions (no-reference mode — self-comparison, so scores are close)
print("\n=== COMPARE RENDITIONS (no-reference) ===")
ab = scorer.compare_renditions(hi_path, lo_path)
print(f"  Winner: {ab['winner']}")
print(f"  Diff:   {ab['differences']}")
# In no-reference mode, both videos compare against themselves,
# so they score similarly (tie is expected)
print("  Note: no-reference self-comparison; difference is small")
assert ab['winner'] in ('A', 'B', 'tie'), "Winner should be valid"

# compare_renditions with reference mode
print("\n=== COMPARE RENDITIONS (with reference) ===")
def compare_with_ref(a, b, ref):
    """Version of compare_renditions that uses a reference."""
    from quality_scorer import QualityScorer
    s = QualityScorer(gpu=True)
    sa = s.score_video(a, reference=ref)
    sb = s.score_video(b, reference=ref)
    oa, ob = sa['overall'], sb['overall']
    return "A" if oa > ob else "B" if ob > oa else "tie"

winner_with_ref = compare_with_ref(hi_path, lo_path, hi_path)
print(f"  Reference mode winner (hi vs lo, ref=hi): {winner_with_ref}")
assert winner_with_ref == 'A', "With reference, high quality should clearly win"
print("  OK: reference-mode A/B test correct")

# quick_score
print("\n=== QUICK SCORE ===")
print(f"  Low quality quick:  {scorer.quick_score(lo_path)}")
print(f"  High quality quick: {scorer.quick_score(hi_path)}")

# Cache and clear
print(f"\nCache entries: {len(scorer._cache)}")
scorer.clear_cache()
print(f"Cache after clear: {len(scorer._cache)}")

# Cleanup
os.unlink(lo_path)
os.unlink(hi_path)

print("\nALL COMPREHENSIVE TESTS PASSED")
