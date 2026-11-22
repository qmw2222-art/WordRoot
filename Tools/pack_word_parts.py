"""Build lossless word-part excerpts from the exact Heart recording used in the lesson."""
from io import BytesIO
from pathlib import Path
import hashlib
import json
import unicodedata
import wave

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def add_word_parts(database, content, timing_file):
    timing = json.loads(Path(timing_file).read_text())
    words = {word["id"]: word for source in sorted(Path(content).glob("family-*.json"))
             for word in json.loads(source.read_text())["words"] if word.get("parts")}
    if words.keys() != timing.keys():
        raise ValueError("The set of recorded words differs from the word-part timing index")
    database.execute("""CREATE TABLE word_parts (
        word_id TEXT NOT NULL, position INTEGER NOT NULL, text TEXT NOT NULL, ipa TEXT NOT NULL,
        word_key TEXT NOT NULL REFERENCES clips(key), start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL,
        mp3 BLOB NOT NULL, PRIMARY KEY (word_id, position)
    ) WITHOUT ROWID""")
    for word_id, word in words.items():
        times = timing[word_id]
        key = unicodedata.normalize("NFC", "\x1f".join(("af_heart", word["pronunciation"], word["word"])))
        row = database.execute("SELECT mp3 FROM clips WHERE key=?", (key,)).fetchone()
        if row is None or hashlib.sha256(row[0]).hexdigest() != times["sha256"]:
            raise ValueError(f"Recheck word-part timing after re-recording {word['word']}")
        audio, rate = sf.read(BytesIO(row[0]), dtype="float32")
        if rate != 16000:
            divisor = np.gcd(16000, rate)
            audio = resample_poly(audio, 16000 // divisor, rate // divisor).astype("float32")
        last = 0
        for index, (part, bounds) in enumerate(zip(word["parts"], times["ranges"], strict=True)):
            start, end = bounds
            if not (last <= start < end <= round(len(audio) / 16)) or end - start < 25:
                raise ValueError(f"Invalid word-part range for {word_id}[{index}]")
            selected = audio[start * 16:end * 16]
            pcm = np.rint(np.clip(selected, -1, 32767 / 32768) * 32768).clip(-32768, 32767).astype("<i2")
            if not len(pcm) or max(abs(pcm.astype("int32"))) < 300:
                raise ValueError(f"Silent word-part in {word_id}[{index}]")
            stream = BytesIO()
            with wave.open(stream, "wb") as entry:
                entry.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                entry.writeframes(bytes(480 * 2) + pcm.tobytes() + bytes(960 * 2))
            database.execute("INSERT INTO word_parts VALUES (?,?,?,?,?,?,?,?)",
                             (word_id, index, part["text"], part["ipa"], key, start, end, stream.getvalue()))
            last = end

