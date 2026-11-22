"""Render the bundled English lessons and Mandarin coaching with local Kokoro v1.0 weights.

Build dependencies: kokoro-onnx 0.5, misaki[en,zh] 0.9.4, en_core_web_sm 3.8, ffmpeg.
The app ships the rendered audio, including lossless short citation forms. An intermediate database permits
interrupted renders to resume. Keep a separate cache per model, frontend and encoding
configuration. The optional --citation-model uses the upstream full-precision Kokoro v1.0
weights for selected English dictionary forms. The final database contains only the requested clips.
"""
import argparse
import hashlib
from collections import defaultdict
from functools import lru_cache
from concurrent.futures import ProcessPoolExecutor
import os
from pathlib import Path
import json
import re
import sqlite3
import subprocess
import unicodedata
import wave

import numpy as np
import onnxruntime as ort

VOICES = ("af_heart",)
MANDARIN = "zf_xiaoxiao"
AUDITION = "Hello. It’s nice to meet you. How are you today?"


def clip_key(voice, text, ipa):
    return unicodedata.normalize("NFC", "\x1f".join((voice, ipa, text)))


def collect_texts(content, words_only):
    phrases = {(AUDITION, ""), ("port", "")}
    readings = {}

    def add_example(text, marked=None):
        phrases.add((text, ""))
        if marked is not None:
            # Misaki accepts a phoneme override around the spoken word. Keep the
            # course sentence verbatim as the public key used by the iPhone.
            plain = re.sub(r"\[([^\]]+)\]\(/[^/)]+/\)", r"\1", marked)
            if plain != text or plain == marked:
                raise ValueError(f"Pronunciation markup changes the visible example: {text!r}")
            if text in readings and readings[text] != marked:
                raise ValueError(f"Conflicting pronunciations for example: {text!r}")
            readings[text] = marked

    for path in sorted(content.glob("family-*.json")):
        family = json.loads(path.read_text())
        phrases.add((family["rootSpoken"], family["rootIPA"]))
        for word in family["words"]:
            phrases.add((word["word"], word.get("pronunciation", "")))
            add_example(word["example"], word.get("exampleReading"))
    basic_file = content / "basic-850.json"
    if basic_file.exists():
        for word in json.loads(basic_file.read_text()):
            phrases.add((word["word"], word["pronunciation"]))
            add_example(word["example"], word.get("exampleReading"))
    if not words_only:
        for path in sorted(content.glob("course-*.json")):
            for day in json.loads(path.read_text()):
                phrases.add((day["bridge"]["text"], ""))
                for line in day["dialogue"]:
                    phrases.add((line["text"], ""))
                for mission in (day["mission"], day.get("beginnerMission", {})):
                    for turn in mission.get("turns", []):
                        add_example(turn["partner"], turn.get("partnerReading"))
                        add_example(turn["reply"], turn.get("replyReading"))
        path = content / "learning-path.json"
        if path.is_file():
            for day in json.loads(path.read_text()):
                for example in day.get("examples", []):
                    sentence = " ".join(piece["text"] for piece in example["pieces"])
                    add_example(sentence, example.get("reading"))
    return sorted(phrases), readings


def spoken_meaning(word):
    first = word["meaning"].split("；", 1)[0]
    cue = word.get("plainCue") or word["memoryCue"]
    if not word.get("parts") and cue.startswith("「" + first + "」"):
        return cue
    return "意思是" + first + "。"


def coach_texts(content):
    days = [day for path in content.glob("course-*.json") for day in json.loads(path.read_text())]
    phrases = {day["guide"] for day in days}
    phrases.update(("几个词里意思相通的小块，叫作词根。先听它，再学第一个词。",
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


# Keep words such as Wi-Fi, contractions and affix hyphens together. A whole
# English phrase goes through the English frontend so it retains its prosody.
ENGLISH_WORD = r"-?[A-Za-z]+(?:['’\-][A-Za-z]+)*-?"
ENGLISH_RUN = re.compile(ENGLISH_WORD + r"(?:[ \t]+" + ENGLISH_WORD + r")*")
HAN = re.compile(r"[\u3400-\u9fff0-9]")


def coach_readings(content):
    """The same spelling can have different stress or vowels in two lessons."""
    hints = defaultdict(lambda: defaultdict(set))
    families = [json.loads(f.read_text()) for f in sorted(content.glob("family-*.json"))]
    roots = {f["id"]: (f["rootSpoken"], f["rootIPA"]) for f in families}
    family_words = {w["id"]: w for f in families for w in f["words"]}
    fragment_ipas = defaultdict(set)
    word_ipas = defaultdict(set)
    for family in families:
        fragment_ipas[family["rootSpoken"].casefold()].add(family["rootIPA"])
        for word in family["words"]:
            for part in word.get("parts", []):
                fragment_ipas[part["text"].casefold()].add(part["ipa"])

    def add(lines, pairs):
        for line in lines:
            if not ENGLISH_RUN.search(line):
                continue
            for spelling, ipa in pairs:
                if spelling and ipa:
                    hints[line][spelling.casefold()].add(ipa)

    for f in families:
        add([f["rootIntro"]], [roots[f["id"]]])
    words = [(word, [roots[f["id"]]]) for f in families for word in f["words"]]
    basic = content / "basic-850.json"
    if basic.exists():
        words += [(word, []) for word in json.loads(basic.read_text())]
    for word, _ in words:
        if word.get("pronunciation"):
            word_ipas[word["word"].casefold()].add(word["pronunciation"])
    # Fill only context-independent matches. Lesson-local senses and affix
    # allomorphs below take precedence over these general teaching readings.
    defaults = {k: next(iter(v)) for k,v in word_ipas.items() if len(v) == 1}
    defaults.update({k: next(iter(v)) for k,v in fragment_ipas.items() if len(v) == 1 and
                     (k.startswith("-") or k.endswith("-") or k not in defaults)})
    for word, root in words:
        pairs = {spelling.casefold(): ipa for spelling, ipa in root}
        for part in word.get("parts", []):
            pairs[part["text"].casefold()] = part["ipa"]
        pairs[word["word"].casefold()] = word.get("pronunciation", "")
        lines = [spoken_meaning(word), word["memoryCue"], word.get("plainCue", ""), word.get("combined", "")]
        lines += [part["meaning"] + "。" for part in word.get("parts", [])]
        whole_ipa = re.sub(r"[ˈˌ.]", "", word.get("pronunciation", ""))
        for line in lines:
            for match in ENGLISH_RUN.finditer(line):
                token = match.group().casefold()
                if token in pairs or not (token.startswith("-") or token.endswith("-")):
                    continue
                # The text may spell a fragment with a hyphen whereas its
                # display part omits it (auto- / auto in autograph).
                if token.strip("-") in pairs:
                    pairs[token] = pairs[token.strip("-")]
                    continue
                def fits(ipa):
                    clean = re.sub(r"[ˈˌ.]", "", ipa)
                    return whole_ipa.endswith(clean) if token.startswith("-") else whole_ipa.startswith(clean)
                matches = [ipa for ipa in fragment_ipas.get(token, ()) if fits(ipa)]
                if len(matches) == 1:
                    pairs[token] = matches[0]
        add(lines, pairs.items())
    for f in sorted(content.glob("course-*.json")):
        for day in json.loads(f.read_text()):
            if day["familyID"] in roots:
                # The first announced sense anchors a contrast such as “contract
                # 有两种重音。说一份合同…”. Keep affix readings from the day's
                # actual words, including ex-, re- and -er.
                pairs = dict([roots[day["familyID"]]])
                for sense in day["wordIDs"]:
                    word = family_words.get(sense)
                    if word:
                        pairs.setdefault(word["word"].casefold(), word["pronunciation"])
                        for part in word.get("parts", []):
                            pairs.setdefault(part["text"].casefold(), part["ipa"])
                add([day["guide"]], pairs.items())
    for line in coach_texts(content):
        for match in ENGLISH_RUN.finditer(line):
            word = match.group().casefold()
            if word not in hints[line]:
                alias = word.strip("-")
                if alias != word and alias in hints[line]:
                    hints[line][word].update(hints[line][alias])
                else:
                    fallback = defaults.get(word, defaults.get(alias))
                    if fallback:
                        hints[line][word].add(fallback)
    return {line: {word: next(iter(ipas)) for word, ipas in readings.items() if len(ipas) == 1}
            for line, readings in hints.items()}


def coach_segments(text, hints):
    """Return contiguous native-language spans. Outside punctuation stays with its phrase."""
    spans = []
    start = 0
    for match in ENGLISH_RUN.finditer(text):
        chinese = text[start:match.start()].strip()
        if HAN.search(chinese):
            spans.append((MANDARIN, chinese, ""))
        elif spans and chinese:
            voice, phrase, hint = spans[-1]
            spans[-1] = (voice, phrase + chinese.strip("「」“”"), hint)
        english = match.group()
        ipa = hints.get(english.casefold(), "")
        # Bind an explicitly identified lesson word's sense even inside a phrase.
        if not ipa:
            def mark(word):
                token = word.group()
                reading = hints.get(token.casefold())
                return f"[{token}](/{ipa_tokens(reading)}/)" if reading else token
            english = re.sub(ENGLISH_WORD, mark, english)
        # Keep an English question mark with its speaker so its intonation survives.
        start = match.end()
        punctuation = re.match(r"[!?.,;:]+", text[start:])
        if punctuation:
            marks = punctuation.group()
            english += marks
            if ipa:
                ipa += marks
            start += len(marks)
        spans.append((VOICES[0], english, ipa))
    tail = text[start:].strip()
    if HAN.search(tail):
        spans.append((MANDARIN, tail, ""))
    elif spans and tail:
        voice, phrase, hint = spans[-1]
        spans[-1] = (voice, phrase + tail.strip("「」“”"), hint)
    return spans


@lru_cache(maxsize=1)
def citation_readings():
    with Path(__file__).with_name("citation_readings.json").open() as f:
        return json.load(f)


def citation_recipe(voice, ipa):
    # Sentence prosody and a homograph's lesson-specific IPA remain authoritative.
    if voice != VOICES[0] or not ipa:
        return None
    return citation_readings().get(ipa.rstrip("!?.,;:"))


@lru_cache(maxsize=None)
def master_path(name):
    if not re.fullmatch(r"[a-z]+", name):
        raise ValueError("Invalid Heart citation name")
    return Path(__file__).with_name("heart-citations") / (name + ".wav")


@lru_cache(maxsize=None)
def cache_recipe(mode):
    if mode and mode.startswith(("master:", "pcm:")):
        with master_path(mode.partition(":")[2]).open("rb") as file:
            return mode + ":" + hashlib.file_digest(file, "sha256").hexdigest()
    return mode


def render_cache_key(voice, spoken, ipa, hints):
    if voice == MANDARIN and ENGLISH_RUN.search(spoken):
        # Old cache entries contain a single Mandarin speaker for the entire line.
        recipe = coach_segments(spoken, hints.get(spoken, {}))
        modes = [cache_recipe(citation_recipe(v, i)) for v, _, i in recipe]
        if any(modes):
            return clip_key("mixed-heart-citation-v1", json.dumps([recipe, modes], ensure_ascii=False), "")
        return clip_key("mixed-heart-xiaoxiao-v1", json.dumps(recipe, ensure_ascii=False), "")
    if mode := cache_recipe(citation_recipe(voice, ipa)):
        return clip_key("heart-citation-v1-" + mode, spoken, ipa)
    return clip_key(voice, spoken, ipa)


def ipa_tokens(ipa):
    # Kokoro uses single tokens for affricates and American r. Place the stress
    # immediately before the vowel, matching the training labels used by Misaki.
    phones = ipa.replace("dʒ", "ʤ").replace("tʃ", "ʧ").replace("r", "ɹ").replace("ɚ", "əɹ")
    for original, kokoro in (("ɝ", "ɜɹ"), ("eɪ", "A"), ("aɪ", "I"), ("oʊ", "O"), ("aʊ", "W"), ("ɔɪ", "Y")):
        phones = phones.replace(original, kokoro)
    return re.sub(r"([ˈˌ])([^ɑæəɛɪʊiueoɔʌɜaAIWOYˈˌ ]+)", r"\2\1", phones)


def load_engine(model_path, voices_path):
    from kokoro_onnx import Kokoro
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model_path), options, providers=["CPUExecutionProvider"])
    return Kokoro.from_session(session, str(voices_path))


def init_worker(model_path, voices_path, citation_path=None):
    global engine, citation_weights, voice_weights
    engine = load_engine(model_path, voices_path)
    citation_weights = Path(citation_path) if citation_path else Path(model_path).with_name("kokoro-v1.0.onnx")
    voice_weights = voices_path
    full_precision_engine.cache_clear()
    recorded_span.cache_clear()


@lru_cache(maxsize=1)
def full_precision_engine():
    if not citation_weights.is_file():
        raise FileNotFoundError("Pass --citation-model with the upstream full-precision kokoro-v1.0.onnx")
    with citation_weights.open("rb") as file:
        if hashlib.file_digest(file, "sha256").hexdigest() != "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5":
            raise ValueError("Unexpected full-precision Kokoro v1.0 citation weights")
    return load_engine(citation_weights, voice_weights)


PHRASE_CONTEXT = {
    "said": ("I sˈɛd ", " əɡˈɛn."),
    "say": ("plˈiz sˈA ", " əɡˈɛn."),
    "clearly": ("wi sˈA ", " klˈɪɹli."),
    "last": ("plˈiz sˈA ðə wˈɜɹd ", "."),
    "comma": ("lˈɪsən, ", ", ðɛn sˈA ɪt."),
}


def final_s(model, speaker):
    # A bare /s/ can make a sentence-trained model invent a vowel. The end of
    # Heart's "miss" has a sustained voiceless /s/ with no following syllable.
    audio, rate = model.create("mˈɪs.", speaker, speed=0.93, is_phonemes=True, trim=False)
    frame = rate // 100
    frames = np.pad(audio, (0, -len(audio) % frame)).reshape(-1, frame)
    spectrum = np.abs(np.fft.rfft(frames * np.hanning(frame), axis=1)) ** 2
    high = spectrum[:, np.fft.rfftfreq(frame, 1 / rate) >= 3500].sum(axis=1)
    rms = np.sqrt(np.mean(frames * frames, axis=1))
    hiss = np.flatnonzero((high > 0.65 * spectrum.sum(axis=1)) & (rms > 0.002))
    runs = np.split(hiss, np.flatnonzero(np.diff(hiss) > 1) + 1)
    tail = next((group for group in reversed(runs) if len(group) >= 10), None)
    if tail is None:
        raise ValueError("Cannot isolate the sustained /s/ in the word miss")
    segment = audio[tail[0] * frame:(tail[-1] + 1) * frame].copy()
    fade = rate // 200
    segment[:fade] *= np.linspace(0, 1, fade)
    segment[-fade:] *= np.linspace(1, 0, fade)
    margin = max(rate // 30, (int(rate * 0.20) - len(segment) + 1) // 2)
    return np.pad(segment, (margin, margin)), rate


def render_citation(phones, speaker, mode, model):
    # Isolated unstressed tokens can lose their onset or release in a sentence-trained voice.
    if "/" in mode:
        style, mode = mode.split("/", 1)
        # Heart includes reference styles at different utterance lengths.
        # Use the auditioned longer reference for difficult single-word recordings.
        index = int(style.removeprefix("style"))
        voice = model.get_voice_style(speaker)
        if not 0 < index < len(voice):
            raise ValueError("Unknown Heart reference style: " + style)
        speaker = np.broadcast_to(voice[index], voice.shape)
    target = phones.rstrip("!?.,;:")
    vowels = r"[ɑæəɛɪʊiueoɔʌɜaAIWOY]"
    if "ˈ" not in target and len(re.findall(vowels, target)) == 1:
        target = re.sub(vowels, lambda m: "ˈ" + m.group(), target, count=1)
    if mode == "final-s":
        if target != "s":
            raise ValueError("The final-s recording is reserved for /s/")
        return final_s(model, speaker)
    if mode in ("direct", "exclaim"):
        punctuation = "!" if mode == "exclaim" else "."
        return model.create(target + punctuation, speaker, speed=0.93, is_phonemes=True, trim=False)
    if mode.startswith("phrase:"):
        # These word boundaries were measured from this Kokoro model's token durations.
        _, context, first, last, length = mode.split(":")
        before, after = PHRASE_CONTEXT[context]
        samples, rate = model.create(before + target + after, speaker, speed=0.93,
                                      is_phonemes=True, trim=False)
        first, last = int(first), int(last)
        if rate != 24_000 or len(samples) != int(length) or not 0 <= first < last <= len(samples):
            raise ValueError("The recorded word boundary no longer matches the reference utterance")
        return samples[first:last], rate
    # Some short syllables have clearer transitions with two supported vowel tokens.
    if mode.endswith("-round"):
        target = target.replace("O", "ou")
        mode = mode.removesuffix("-round")
    if mode.endswith("-vowel"):
        target = target.replace("O", "oʊ").replace("Y", "ɔɪ").replace("A", "eɪ").replace("I", "aɪ")
        mode = mode.removesuffix("-vowel")
    if mode == "isolated":
        return model.create(target + ".", speaker, speed=0.93, is_phonemes=True)
    following = {"before-again": "əɡˈɛn", "before-thanks": "θˈæŋk ju", "repeat-first": target}
    if mode in following:
        carrier = following[mode]
        phrase = target + ". " + carrier
    else:
        carrier = {"say": "sˈA", "listen": "lˈɪsən", "word": "ðə wˈɜɹd ɪz",
                   "repeat-last": target, "close": ""}[mode]
        phrase = carrier + ". " + target if carrier else target.replace("O", "əʊ")
    signal, rate = model.create(phrase + ".", speaker, speed=0.93, is_phonemes=True, trim=False)
    frame = round(rate * 0.005)
    chunks = np.pad(signal, (0, -len(signal) % frame)).reshape(-1, frame)
    energy = np.sqrt(np.mean(chunks * chunks, axis=1))
    active = np.flatnonzero(energy > max(0.0025, 0.023 * energy.max()))
    groups = np.split(active, np.flatnonzero(np.diff(active) * 0.005 > 0.09) + 1)
    groups = [g for g in groups if len(g) * 0.005 > 0.045]
    if len(groups) != (2 if carrier else 1):
        raise ValueError("Cannot safely isolate the target after its carrier: " + phones)
    target_frames = groups[0] if mode in following else groups[-1]
    margin = round(rate * 0.045)
    start = max(0, int(target_frames[0]) * frame - margin)
    end = min(len(signal), (int(target_frames[-1]) + 1) * frame + margin)
    segment = signal[start:end]
    if mode == "close":
        # Keep the same PCM16 precision as the audition used for this close-mic cut.
        segment = np.floor(np.clip(segment, -1.0, 32767 / 32768) * 32768) / 32768
    return segment, rate


def heart_master(name):
    # These lossless masters were generated with af_heart and checked against US
    # speakers. The word button and the same word in a bilingual cue share the PCM.
    with wave.open(str(master_path(name)), "rb") as file:
        if (file.getnchannels(), file.getsampwidth(), file.getframerate()) != (1, 2, 24_000):
            raise ValueError("Unexpected Heart master format: " + name)
        return np.frombuffer(file.readframes(file.getnframes()), dtype="<i2").astype(np.float32) / 32768, 24_000


@lru_cache(maxsize=192)
def recorded_span(speaker, phones, mode):
    if mode:
        if mode.startswith("pcm:") and speaker == VOICES[0]:
            # Mixed Chinese/English prompts use the same citation at the coach's 24 kHz rate.
            process = subprocess.run([
                "ffmpeg", "-v", "error", "-i", str(master_path(mode.removeprefix("pcm:"))),
                "-ar", "24000", "-ac", "1", "-f", "f32le", "pipe:1",
            ], capture_output=True, check=True)
            return np.frombuffer(process.stdout, dtype="<f4"), 24_000
        if mode.startswith("master:") and speaker == VOICES[0]:
            return heart_master(mode.removeprefix("master:"))
        if mode.startswith("full/"):
            return render_citation(phones, speaker, mode.removeprefix("full/"), full_precision_engine())
        return render_citation(phones, speaker, mode, engine)
    return engine.create(phones, speaker, speed=0.93, is_phonemes=True)


def render(job):
    key, voice, phonemes = job
    spans = phonemes
    if len(spans) == 1 and voice == VOICES[0] and (mode := spans[0][2]) and mode.startswith("pcm:"):
        path = master_path(mode.removeprefix("pcm:"))
        # Keep these brief sounds byte-identical to the audition. AVAudioPlayer detects WAV from its header.
        with wave.open(str(path), "rb") as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 16_000) or wav.getnframes() < 3_040:
                raise ValueError(f"Unexpected lossless citation format for {key!r}")
        return key, path.read_bytes()
    pieces = []
    for speaker, phones, mode in spans:
        if not phones or not set(phones) <= engine.tokenizer.vocab.keys():
            raise ValueError(f"Unsupported pronunciation for {key!r}: {phones!r}")
        recording, rate = recorded_span(speaker, phones, mode)
        signal = recording.copy()
        peak = float(np.max(np.abs(signal)))
        if not np.isfinite(signal).all() or peak < 0.03 or len(signal) < rate * 0.10:
            raise ValueError(f"Empty or damaged speech in {key!r}")
        rms = np.sqrt(np.mean(np.square(signal)))
        signal *= min(0.095 / max(rms, 0.001), 0.86 / peak)
        if len(spans) > 1:
            # Trim long model boundary silences before joining languages. Keep
            # soft consonants and a short natural breath between the speakers.
            active = np.flatnonzero(np.abs(signal) > 0.004)
            margin = int(rate * 0.025)
            signal = signal[max(0, active[0] - margin):active[-1] + margin + 1]
            if pieces:
                pieces.append(np.zeros(int(rate * 0.045), dtype=signal.dtype))
        pieces.append(signal)
    audio = np.concatenate(pieces)
    if len(audio) < rate * 0.19:
        raise ValueError(f"Recording is too short for {key!r}")
    if len(spans) != 1 or spans[0][2] != "close":
        audio = np.pad(audio, (int(rate * 0.04), int(rate * 0.13)))
    bitrate = "128k" if any(mode and mode.startswith(("master:", "pcm:")) for _, _, mode in spans) else "64k"
    encoded = subprocess.run([
        "ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(rate), "-ac", "1",
        "-i", "pipe:0", "-c:a", "libmp3lame", "-b:a", bitrate, "-f", "mp3", "pipe:1",
    ], input=audio.astype("<f4").tobytes(), capture_output=True, check=True)
    return key, encoded.stdout


def phonemize(remaining, hints=None):
    hints = hints or {}
    import espeakng_loader
    from misaki import en, espeak
    old_path = Path.cwd()
    # eSpeak's compiled path buffer is short on macOS. Give it a short data path.
    os.chdir(Path(espeakng_loader.get_data_path()).parent)
    os.environ["ESPEAK_DATA_PATH"] = "espeak-ng-data"
    try:
        converter = en.G2P(british=False, fallback=espeak.EspeakFallback(british=False))
        from misaki.zh import ZHG2P
        chinese = ZHG2P() if any(v == MANDARIN for _, v, _, _ in remaining) else None

        @lru_cache(maxsize=None)
        def phones(is_chinese, text, ipa):
            if not is_chinese:
                return ipa_tokens(ipa) if ipa else converter(text)[0].strip()
            text = re.sub(r"[“”‘’「」《》（）()]", " ", text).replace("……", "，").replace("/", "或")
            return chinese(text)[0].strip()

        prepared = []
        for key, voice, text, ipa in remaining:
            if voice == MANDARIN and ENGLISH_RUN.search(text):
                spans = coach_segments(text, hints.get(text, {}))
                tokens = [(v, phones(v == MANDARIN, phrase, reading), citation_recipe(v, reading))
                          for v, phrase, reading in spans]
            else:
                tokens = [(voice, phones(voice == MANDARIN, text, ipa), citation_recipe(voice, ipa))]
            prepared.append((key, voice, tokens))
        return prepared
    finally:
        os.chdir(old_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("content", "model", "voices", "cache", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--citation-model", type=Path, help="Full-precision kokoro-v1.0.onnx for selected English word readings")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--words-only", action="store_true")
    args = parser.parse_args()
    texts, readings = collect_texts(args.content, args.words_only)
    hints = {} if args.words_only else coach_readings(args.content)
    jobs = [(clip_key(v, text, ipa), v, readings.get(text, text) if not ipa else text, ipa)
            for text, ipa in texts for v in VOICES]
    if not args.words_only:
        jobs += [(clip_key(MANDARIN, t, ""), MANDARIN, t, "") for t in coach_texts(args.content)]
    with sqlite3.connect(args.cache) as cache:
        schema = "CREATE TABLE IF NOT EXISTS clips (key TEXT PRIMARY KEY, mp3 BLOB NOT NULL) WITHOUT ROWID"
        cache.execute(schema)
        existing = {row[0] for row in cache.execute("SELECT key FROM clips")}
        # Cache by what is pronounced so an edited reading cannot reuse stale audio.
        cache_keys = {key: render_cache_key(voice, spoken, ipa, hints) for key, voice, spoken, ipa in jobs}
        remaining = [(cache_keys[key], voice, spoken, ipa) for key, voice, spoken, ipa in jobs
                     if cache_keys[key] not in existing]
        print(f"Requested {len(jobs)} recordings, rendering {len(remaining)}", flush=True)
        if remaining:
            prepared = phonemize(remaining, hints)
            from kokoro_onnx.config import DEFAULT_VOCAB
            for key, voice, reading in prepared:
                for _, tokens, _ in reading:
                    if not tokens or set(tokens) - DEFAULT_VOCAB.keys():
                        raise ValueError(f"Unsupported frontend tokens for {key!r}: {tokens!r}")
            with ProcessPoolExecutor(max_workers=args.workers, initializer=init_worker,
                                     initargs=(str(args.model.resolve()), str(args.voices.resolve()), args.citation_model)) as pool:
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
                    blob, = cache.execute("SELECT mp3 FROM clips WHERE key=?", (cache_keys[key],)).fetchone()
                    assert len(blob) > 1000, key
                    result.execute("INSERT INTO clips VALUES (?,?)", (key, blob))
                if not args.words_only:
                    from pack_word_parts import add_word_parts
                    add_word_parts(result, args.content, Path(__file__).with_name("word_part_times.json"))
                result.commit()
                assert result.execute("PRAGMA integrity_check").fetchone() == ("ok",)
            temporary.replace(args.output)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"{len(jobs)} recordings written to {args.output}", flush=True)


if __name__ == "__main__":
    main()
