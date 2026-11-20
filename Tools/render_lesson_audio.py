"""Render the bundled English lessons and Mandarin coaching with local Kokoro v1.0 weights.

Build dependencies: kokoro-onnx 0.5, misaki[en,zh] 0.9.4, en_core_web_sm 3.8, ffmpeg.
The app ships only the resulting MP3 recordings. An intermediate database permits
interrupted renders to resume. Keep a separate cache per model, frontend and encoding
configuration. The final database contains only the requested clips.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
import os
from pathlib import Path
import json
import re
import sqlite3
import subprocess
import unicodedata

import numpy as np
import onnxruntime as ort

VOICES = ("af_heart",)
MANDARIN = "zf_xiaoxiao"
AUDITION = "Hello. It’s nice to meet you. How are you today?"


def clip_key(voice, text, ipa):
    return unicodedata.normalize("NFC", "\x1f".join((voice, ipa, text)))


def collect_texts(content, words_only):
    phrases = {(AUDITION, ""), ("port", "")}
    for path in sorted(content.glob("family-*.json")):
        family = json.loads(path.read_text())
        phrases.add((family["rootSpoken"], family["rootIPA"]))
        for word in family["words"]:
            for part in word.get("parts", []):
                phrases.add((part["text"], part["ipa"]))
            phrases.add((word["word"], word.get("pronunciation", "")))
            phrases.add((word["example"], ""))
    basic_file = content / "basic-850.json"
    if basic_file.exists():
        for word in json.loads(basic_file.read_text()):
            phrases.add((word["word"], word["pronunciation"]))
            phrases.add((word["example"], ""))
    if not words_only:
        for path in sorted(content.glob("course-*.json")):
            for day in json.loads(path.read_text()):
                phrases.add((day["bridge"]["text"], ""))
                for line in day["dialogue"]:
                    phrases.add((line["text"], ""))
                for turn in day.get("mission", {}).get("turns", []):
                    phrases.update(((turn["partner"], ""), (turn["reply"], "")))
    return sorted(phrases)


def spoken_meaning(word):
    first = word["meaning"].split("；", 1)[0]
    cue = word.get("plainCue") or word["memoryCue"]
    if not word.get("parts") and cue.startswith("「" + first + "」"):
        return cue
    return "意思是" + first + "。"


def coach_texts(content):
    days = [day for path in content.glob("course-*.json") for day in json.loads(path.read_text())]
    phrases = {day["guide"] for day in days}
    phrases.update(("有些词里藏着同一小块，叫作词根。先听这一块怎么读。",
                    "今天先听一个词根。", "今天先听一个生活里常用的词。"))
    for path in content.glob("family-*.json"):
        family = json.loads(path.read_text())
        phrases.add(family["rootIntro"])
        for word in family["words"]:
            phrases.add(spoken_meaning(word))
            phrases.add(word["memoryCue"])
            phrases.add(word.get("plainCue", word["memoryCue"]))
            if word.get("parts"):
                phrases.add(word["combined"])
                phrases.update(part["meaning"] + "。" for part in word["parts"])
    basic_file = content / "basic-850.json"
    if basic_file.exists():
        for word in json.loads(basic_file.read_text()):
            phrases.add(spoken_meaning(word))
            phrases.add(word["memoryCue"])
            phrases.add(word.get("plainCue", word["memoryCue"]))
    return sorted(phrases)


def ipa_tokens(ipa):
    # Kokoro uses single tokens for affricates and American r. Place the stress
    # immediately before the vowel, matching the training labels used by Misaki.
    phones = ipa.replace("dʒ", "ʤ").replace("tʃ", "ʧ").replace("r", "ɹ").replace("ɚ", "əɹ")
    for original, kokoro in (("ɝ", "ɜɹ"), ("eɪ", "A"), ("aɪ", "I"), ("oʊ", "O"), ("aʊ", "W"), ("ɔɪ", "Y")):
        phones = phones.replace(original, kokoro)
    return re.sub(r"([ˈˌ])([^ɑæəɛɪʊiueoɔʌɜaAIWOYˈˌ ]+)", r"\2\1", phones)


def init_worker(model_path, voices_path):
    from kokoro_onnx import Kokoro
    global engine
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(model_path, options, providers=["CPUExecutionProvider"])
    engine = Kokoro.from_session(session, voices_path)


def render(job):
    key, voice, phonemes = job
    if not phonemes or not set(phonemes) <= engine.tokenizer.vocab.keys():
        raise ValueError(f"Unsupported pronunciation for {key!r}: {phonemes}")
    audio, rate = engine.create(phonemes, voice, speed=0.93, is_phonemes=True)
    peak = float(np.max(np.abs(audio)))
    if not np.isfinite(audio).all() or peak < 0.03 or len(audio) < rate * 0.19:
        raise ValueError(f"Empty or damaged recording: {key!r}")
    # Match levels between speakers, leaving headroom for the MP3 encoder.
    rms = np.sqrt(np.mean(np.square(audio)))
    audio *= min(0.095 / max(rms, 0.001), 0.86 / peak)
    audio = np.pad(audio, (int(rate * 0.04), int(rate * 0.13)))
    encoded = subprocess.run([
        "ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(rate), "-ac", "1",
        "-i", "pipe:0", "-c:a", "libmp3lame", "-b:a", "64k", "-f", "mp3", "pipe:1",
    ], input=audio.astype("<f4").tobytes(), capture_output=True, check=True)
    return key, encoded.stdout


def phonemize(remaining):
    import espeakng_loader
    from misaki import en, espeak
    old_path = Path.cwd()
    # eSpeak's compiled path buffer is short on macOS. Give it a short data path.
    os.chdir(Path(espeakng_loader.get_data_path()).parent)
    os.environ["ESPEAK_DATA_PATH"] = "espeak-ng-data"
    try:
        converter = en.G2P(british=False, fallback=espeak.EspeakFallback(british=False))
        from misaki.zh import ZHG2P
        from functools import lru_cache
        chinese = ZHG2P() if any(v == MANDARIN for _, v, _, _ in remaining) else None

        @lru_cache(maxsize=None)
        def phones(is_chinese, text, ipa):
            if not is_chinese:
                return ipa_tokens(ipa) if ipa else converter(text)[0].strip()
            # The Mandarin frontend leaves English spelling untouched. Pronounce
            # embedded English words with the same frontend as the lesson audio.
            text = re.sub(r"[“”‘’「」《》（）()]", " ", text).replace("……", "，").replace("/", "或")
            text = re.sub(r"(?<=[A-Za-z])-(?![A-Za-z])|(?<![A-Za-z])-(?=[A-Za-z])", "", text)
            chunks = re.split(r"([A-Za-z]+(?:['-][A-Za-z]+)*)", text)
            return " ".join(
                converter(chunk)[0].strip() if re.match(r"[A-Za-z]", chunk)
                else chinese(chunk)[0].strip()
                for chunk in chunks if chunk.strip()
            ).strip()

        return [(key, voice, phones(voice == MANDARIN, text, ipa))
                for key, voice, text, ipa in remaining]
    finally:
        os.chdir(old_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("content", "model", "voices", "cache", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--words-only", action="store_true")
    args = parser.parse_args()
    texts = collect_texts(args.content, args.words_only)
    jobs = [(clip_key(v, t, i), v, t, i) for t, i in texts for v in VOICES]
    if not args.words_only:
        jobs += [(clip_key(MANDARIN, t, ""), MANDARIN, t, "") for t in coach_texts(args.content)]
    with sqlite3.connect(args.cache) as cache:
        schema = "CREATE TABLE IF NOT EXISTS clips (key TEXT PRIMARY KEY, mp3 BLOB NOT NULL) WITHOUT ROWID"
        cache.execute(schema)
        existing = {row[0] for row in cache.execute("SELECT key FROM clips")}
        remaining = [job for job in jobs if job[0] not in existing]
        print(f"Requested {len(jobs)} recordings, rendering {len(remaining)}", flush=True)
        if remaining:
            prepared = phonemize(remaining)
            from kokoro_onnx.config import DEFAULT_VOCAB
            invalid = [(key, sorted(set(tokens) - DEFAULT_VOCAB.keys())) for key, _, tokens in prepared
                       if not tokens or set(tokens) - DEFAULT_VOCAB.keys()]
            if invalid:
                raise ValueError(f"Unsupported frontend tokens: {invalid}")
            with ProcessPoolExecutor(max_workers=args.workers, initializer=init_worker,
                                     initargs=(str(args.model.resolve()), str(args.voices.resolve()))) as pool:
                for index, result in enumerate(pool.map(render, prepared, chunksize=2), start=1):
                    cache.execute("INSERT INTO clips VALUES (?,?)", result)
                    if index % 50 == 0:
                        cache.commit()
                        print(f"{index}/{len(prepared)}", flush=True)
            cache.commit()
        temporary = args.output.with_suffix(".partial")
        temporary.unlink(missing_ok=True)
        try:
            with sqlite3.connect(temporary) as result:
                result.execute(schema)
                for key, *_ in jobs:
                    blob, = cache.execute("SELECT mp3 FROM clips WHERE key=?", (key,)).fetchone()
                    assert len(blob) > 1000, key
                    result.execute("INSERT INTO clips VALUES (?,?)", (key, blob))
                result.commit()
                assert result.execute("PRAGMA integrity_check").fetchone() == ("ok",)
            temporary.replace(args.output)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"{len(jobs)} recordings written to {args.output}", flush=True)


if __name__ == "__main__":
    main()
