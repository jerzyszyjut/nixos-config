"""Build two-language subtitle files for language learning.

For every video under the given directories that has subtitles in both
languages, write "<video>.<A>+<B>.<a>.srt" showing language A with language
B in italics underneath. Sources are the external .srt files Bazarr
downloads, falling back to a text subtitle track embedded in the video.

Re-run safe: an output newer than both of its sources is left alone.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

VIDEO_EXT = {".mkv", ".mp4", ".m4v", ".avi"}
TEXT_CODECS = {"subrip", "ass", "ssa", "mov_text", "webvtt"}
CODES = {
    "en": {"en", "eng", "english"},
    "de": {"de", "ger", "deu", "german"},
    "pl": {"pl", "pol", "polish"},
}
SNAP = 0.7       # seconds: B's cue edges this close to A's are aligned to A
MIN_LEN = 0.2    # seconds: shorter fragments are folded into a neighbour
TS = re.compile(r"(\d+):(\d\d):(\d\d)[,.](\d{1,3})")
TAG = re.compile(r"<[^>]+>|\{\\[^}]*\}")


def parse_srt(path):
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("latin-1")
    for enc in ("utf-8-sig", "cp1250"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    cues = []
    for block in re.split(r"\r?\n\s*\r?\n", text.strip()):
        lines = block.splitlines()
        idx = next((i for i, ln in enumerate(lines) if "-->" in ln), None)
        if idx is None:
            continue
        times = TS.findall(lines[idx])
        if len(times) < 2:
            continue
        start, end = (
            int(h) * 3600 + int(m) * 60 + int(s) + int(ms.ljust(3, "0")) / 1000
            for h, m, s, ms in times[:2]
        )
        body = [TAG.sub("", ln).strip() for ln in lines[idx + 1:]]
        body = " ".join(ln for ln in body if ln)
        if body and end > start:
            cues.append([start, end, body])
    cues.sort()
    return cues


def snap(b_cues, a_cues):
    starts = [c[0] for c in a_cues]
    ends = [c[1] for c in a_cues]

    def nearest(value, pool):
        best = min(pool, key=lambda p: abs(p - value), default=value)
        return best if abs(best - value) <= SNAP else value

    for cue in b_cues:
        start, end = nearest(cue[0], starts), nearest(cue[1], ends)
        if end > start:
            cue[0], cue[1] = start, end


def merge(a_cues, b_cues):
    snap(b_cues, a_cues)
    edges = sorted({t for c in a_cues + b_cues for t in c[:2]})
    out = []
    for t0, t1 in zip(edges, edges[1:]):
        mid = (t0 + t1) / 2
        a = " ".join(c[2] for c in a_cues if c[0] <= mid < c[1])
        b = " ".join(c[2] for c in b_cues if c[0] <= mid < c[1])
        if not a and not b:
            continue
        text = "\n".join(x for x in (a, f"<i>{b}</i>" if b else "") if x)
        if out and out[-1][2] == text and abs(out[-1][1] - t0) < 0.01:
            out[-1][1] = t1
        elif out and t1 - t0 < MIN_LEN and abs(out[-1][1] - t0) < 0.01:
            out[-1][1] = t1
        else:
            out.append([t0, t1, text])
    return out


def fmt(t):
    ms = round(t * 1000)
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def external(video, lang):
    base = os.path.splitext(video)[0]
    folder = os.path.dirname(video)
    best = None
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not path.startswith(base + ".") or not name.lower().endswith(".srt"):
            continue
        tokens = name[len(os.path.basename(base)) + 1:-4].lower().split(".")
        if any("+" in t for t in tokens) or not set(tokens) & CODES[lang]:
            continue
        rank = ("forced" in tokens, "hi" in tokens or "sdh" in tokens)
        if best is None or rank < best[0]:
            best = (rank, path)
    return best[1] if best else None


def embedded(video, lang, ffmpeg, tmpdir):
    try:
        probe = json.loads(subprocess.run(
            [os.path.join(ffmpeg, "ffprobe"), "-v", "error", "-select_streams", "s",
             "-show_entries", "stream=codec_name:stream_tags=language,title:disposition=forced",
             "-of", "json", video],
            capture_output=True, text=True, timeout=120).stdout or "{}")
    except (subprocess.SubprocessError, json.JSONDecodeError):
        return None
    # Plain tracks first; an SDH one (sound descriptions included) only when
    # it is all there is — Dark's second season ships German as SDH only.
    found = []
    for n, stream in enumerate(probe.get("streams", [])):
        tags = stream.get("tags", {})
        title = tags.get("title", "").lower()
        disposition = stream.get("disposition", {})
        if (stream.get("codec_name") in TEXT_CODECS
                and tags.get("language", "").lower() in CODES[lang]
                and not disposition.get("forced")
                and "commentary" not in title and "forced" not in title):
            sdh = "sdh" in title or bool(disposition.get("hearing_impaired"))
            found.append((sdh, n))
    for _, n in sorted(found):
        out = os.path.join(tmpdir, f"{lang}.srt")
        done = subprocess.run(
            [os.path.join(ffmpeg, "ffmpeg"), "-v", "error", "-y", "-i", video,
             "-map", f"0:s:{n}", "-f", "srt", out],
            capture_output=True, timeout=600)
        if done.returncode == 0 and os.path.getsize(out) > 0:
            return out
    return None


def main():
    lang_a, lang_b, ffmpeg, *roots = sys.argv[1:]
    made = kept = 0
    for root in roots:
        for folder, _, files in os.walk(root):
            for name in files:
                if os.path.splitext(name)[1].lower() not in VIDEO_EXT:
                    continue
                video = os.path.join(folder, name)
                stem = f"{os.path.splitext(video)[0]}.{lang_a.upper()}+{lang_b.upper()}"
                target = f"{stem}.{lang_a}.srt"
                if os.path.exists(f"{stem}.und.srt"):  # name used before 2026-09-30
                    os.replace(f"{stem}.und.srt", target)
                with tempfile.TemporaryDirectory() as tmp:
                    ext_a, ext_b = external(video, lang_a), external(video, lang_b)
                    newest = max((os.path.getmtime(p) for p in (ext_a, ext_b, video) if p))
                    if os.path.exists(target) and os.path.getmtime(target) >= newest:
                        kept += 1
                        continue
                    src_a = ext_a or embedded(video, lang_a, ffmpeg, tmp)
                    src_b = ext_b or embedded(video, lang_b, ffmpeg, tmp)
                    if not src_a or not src_b:
                        continue
                    cues = merge(parse_srt(src_a), parse_srt(src_b))
                    if not cues:
                        continue
                    with open(target + ".tmp", "w", encoding="utf-8") as f:
                        for i, (start, end, text) in enumerate(cues, 1):
                            f.write(f"{i}\n{fmt(start)} --> {fmt(end)}\n{text}\n\n")
                    os.replace(target + ".tmp", target)
                    os.chmod(target, 0o664)
                    made += 1
                    print(f"wrote {target} ({len(cues)} cues)")
    print(f"done: {made} written, {kept} already up to date")


main()
