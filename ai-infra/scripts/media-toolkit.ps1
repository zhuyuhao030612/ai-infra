# PHS Media Toolkit — video/image editing via FFmpeg + Python
param([string]$Action, [string]$Input, [string]$Output, [string]$Params)

$ErrorActionPreference = "SilentlyContinue"
$FFMPEG = "D:\PHS\prism\_bundled\ffmpeg\ffmpeg.exe"
$FFPROBE = "D:\PHS\prism\_bundled\ffmpeg\ffprobe.exe"
$PYTHON = "python"

function ff([string]$cmdStr) {
    $fullCmd = "`"$FFMPEG`" -y $cmdStr"
    cmd /c $fullCmd 2>&1 | Out-Null
}

switch ($Action) {
    "trim" {
        # trim video: -Params "start=5,duration=10" or just "5,10"
        $p = $Params -split ','
        $start = $p[0]; $dur = if ($p.Count -gt 1) { $p[1] } else { "9999" }
        ff "-ss $start -i `"$Input`" -t $dur -c copy `"$Output`""
        return "Trimmed: $Output"
    }
    "concat" {
        # concat videos: Input is list file
        ff "-f concat -safe 0 -i `"$Input`" -c copy `"$Output`""
        return "Concatenated: $Output"
    }
    "resize" {
        # resize: -Params "1080,1920"
        $p = $Params -split ','
        ff "-i `"$Input`" -vf scale=$($p[0]):$($p[1]):force_original_aspect_ratio=decrease,pad=$($p[0]):$($p[1]):(ow-iw)/2:(oh-ih)/2 -c:v libx264 -preset veryfast -c:a aac `"$Output`""
        return "Resized: $Output"
    }
    "overlay_text" {
        # add text overlay: -Params "text=Hello,x=100,y=100,size=48,color=white"
        # Parse key=value pairs
        $vals = @{}
        foreach ($kv in $Params -split ',') {
            $k, $v = $kv -split '=', 2
            $vals[$k] = $v
        }
        $text = $vals["text"] ?? "Text"
        $x = $vals["x"] ?? "100"
        $y = $vals["y"] ?? "100"
        $size = $vals["size"] ?? "48"
        $color = $vals["color"] ?? "white"
        ff "-i `"$Input`" -vf `"drawtext=text='$text':x=$x:y=$y:fontsize=$size:fontcolor=$color`" -c:a copy `"$Output`""
        return "Overlay added: $Output"
    }
    "extract_audio" {
        ff "-i `"$Input`" -vn -c:a aac `"$Output`""
        return "Audio extracted: $Output"
    }
    "replace_audio" {
        # -Params is the new audio file path
        ff "-i `"$Input`" -i `"$Params`" -c:v copy -map 0:v:0 -map 1:a:0 -shortest `"$Output`""
        return "Audio replaced: $Output"
    }
    "to_gif" {
        ff "-i `"$Input`" -vf fps=10,scale=480:-1 -loop 0 `"$Output`""
        return "GIF: $Output"
    }
    "speed" {
        # speed up/down: -Params "2.0" (2x) or "0.5" (half)
        $s = [float]$Params
        $setpts = 1.0 / $s
        ff "-i `"$Input`" -filter_complex `"[0:v]setpts=$($setpts.ToString('0.00',[System.Globalization.CultureInfo]::InvariantCulture))*PTS[v];[0:a]atempo=$($Params)[a]`" -map `"[v]`" -map `"[a]`" `"$Output`""
        return "Speed changed: $Output"
    }
    "watermark" {
        # add image watermark: -Params is watermark image path
        ff "-i `"$Input`" -i `"$Params`" -filter_complex overlay=10:10 `"$Output`""
        return "Watermark added: $Output"
    }
    "crop" {
        # crop: -Params "x,y,w,h"
        $p = $Params -split ','
        ff "-i `"$Input`" -vf crop=$($p[2]):$($p[3]):$($p[0]):$($p[1]) -c:a copy `"$Output`""
        return "Cropped: $Output"
    }
    "mute" {
        ff "-i `"$Input`" -an -c:v copy `"$Output`""
        return "Muted: $Output"
    }
    "probe" {
        & $FFPROBE -v quiet -print_format json -show_format -show_streams $Input 2>&1
        return ""
    }
    "edit_image" {
        # Python-based image editing: resize/crop/flip/adjust
        $script = @"
import sys, json
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
from pathlib import Path

action, path, out, params = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else ''
img = Image.open(path)
if action == 'resize':
    w, h = map(int, params.split(','))
    img = img.resize((w, h), Image.LANCZOS)
elif action == 'crop':
    x, y, w, h = map(int, params.split(','))
    img = img.crop((x, y, x+w, y+h))
elif action == 'flip_h':
    img = ImageOps.mirror(img)
elif action == 'flip_v':
    img = ImageOps.flip(img)
elif action == 'rotate':
    img = img.rotate(float(params), expand=True)
elif action == 'brightness':
    img = ImageEnhance.Brightness(img).enhance(float(params))
elif action == 'contrast':
    img = ImageEnhance.Contrast(img).enhance(float(params))
elif action == 'saturation':
    img = ImageEnhance.Color(img).enhance(float(params))
elif action == 'sharpen':
    img = img.filter(ImageFilter.SHARPEN)
elif action == 'blur':
    img = img.filter(ImageFilter.GaussianBlur(radius=int(params) if params else 5))
elif action == 'grayscale':
    img = ImageOps.grayscale(img)
elif action == 'auto_contrast':
    img = ImageOps.autocontrast(img)
elif action == 'info':
    print(json.dumps({'size': list(img.size), 'mode': img.mode, 'format': img.format}))
    sys.exit(0)
elif action == 'remove_bg_white':
    img = img.convert('RGBA')
    datas = img.getdata()
    new = [(255,255,255,0) if all(c > 200 for c in item[:3]) else item for item in datas]
    img.putdata(new)
img.save(out)
print(f'OK: {out}')
"@
        $scriptPath = "$env:TEMP\phs_img_edit.py"
        $script | Out-File $scriptPath -Encoding UTF8
        $r = & $PYTHON $scriptPath $Input $Output $Params 2>&1
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        return $r
    }
    "info" {
        return "Actions: trim, concat, resize, overlay_text, extract_audio, replace_audio, to_gif, speed, watermark, crop, mute, probe, edit_image"
    }
    default {
        return "Unknown: $Action"
    }
}
