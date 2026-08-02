#!/usr/bin/env python3
"""Démon de transcription Whisper pour Goldodict.

Lit des commandes JSON sur stdin, une par ligne, et répond de même sur stdout.
Le modèle reste chargé entre deux dictées : le relancer à chaque fois coûterait
plusieurs secondes.

L'audio est reçu en PCM brut, virgule flottante 32 bits, 16 kHz, mono, écrit dans
un fichier temporaire. Le tableau est passé directement à `mlx_whisper.transcribe`,
ce qui court-circuite `ffmpeg` — absent de la machine et requis par l'interface en
ligne de commande de mlx_whisper.

Commandes
    {"cmd": "ping"}
    {"cmd": "models"}
    {"cmd": "load", "model": "mlx-community/whisper-large-v3-turbo"}
    {"cmd": "transcribe", "path": "/tmp/x.f32", "language": "fr", "prompt": "..."}
"""

import json
import os
import sys
import traceback

DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
SAMPLE_RATE = 16000

_state = {"model": None}


def respond(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def cached_models():
    """Modèles Whisper réellement présents dans le cache HuggingFace."""
    hub = os.path.expanduser("~/.cache/huggingface/hub")
    if not os.path.isdir(hub):
        return []
    found = []
    for name in os.listdir(hub):
        if not name.startswith("models--"):
            continue
        repo = name[len("models--"):].replace("--", "/")
        if "whisper" in repo.lower():
            found.append(repo)
    return sorted(found)


def load_audio(path):
    import numpy as np

    audio = np.fromfile(path, dtype=np.float32)
    return audio


def do_transcribe(request):
    import mlx_whisper

    model = request.get("model") or _state["model"] or DEFAULT_MODEL
    _state["model"] = model

    audio = load_audio(request["path"])
    if audio.size == 0:
        return {"ok": True, "text": "", "seconds": 0.0}

    options = {
        "path_or_hf_repo": model,
        "language": request.get("language", "fr"),
        "fp16": True,
        "condition_on_previous_text": False,
    }
    prompt = request.get("prompt")
    if prompt:
        # Oriente la reconnaissance vers le vocabulaire attendu : noms propres,
        # abréviations, termes de procédure.
        options["initial_prompt"] = prompt

    result = mlx_whisper.transcribe(audio, **options)
    return {
        "ok": True,
        "text": (result.get("text") or "").strip(),
        "seconds": round(audio.size / SAMPLE_RATE, 3),
    }


def handle(request):
    command = request.get("cmd")

    if command == "ping":
        return {"ok": True, "pong": True}

    if command == "models":
        return {"ok": True, "models": cached_models(), "default": DEFAULT_MODEL}

    if command == "load":
        # Les poids sont chargés ici, et pas seulement le module. L'import de
        # mlx_whisper coûte déjà 1,7 s, le chargement du modèle 1,7 s de plus, et
        # les deux étaient payés par la première dictée. `load_model` remplit le
        # cache que `transcribe` consulte ensuite.
        from mlx_whisper import load_models

        model = request.get("model") or DEFAULT_MODEL
        load_models.load_model(model)
        _state["model"] = model
        return {"ok": True, "model": model}

    if command == "transcribe":
        return do_transcribe(request)

    return {"ok": False, "error": f"commande inconnue : {command}"}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            respond({"ok": False, "error": f"JSON invalide : {error}"})
            continue

        try:
            respond(handle(request))
        except Exception as error:  # noqa: BLE001
            respond({
                "ok": False,
                "error": str(error),
                "trace": traceback.format_exc(limit=3),
            })


if __name__ == "__main__":
    main()
