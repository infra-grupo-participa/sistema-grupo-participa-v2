"""
Worker local da fila de transcricao do modulo de depoimentos.

Dependencias:
  pip install faster-whisper google-auth requests

Uso:
  python infra/scripts/depoimentos_transcriber.py --once
  python infra/scripts/depoimentos_transcriber.py --watch --interval 15
"""

from __future__ import annotations

import argparse
import base64
import json
import logging
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import requests
from faster_whisper import WhisperModel
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account


ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "app" / ".env"
UTC = timezone.utc
LOG = logging.getLogger("dep_transcriber")
STALE_LOCK_MINUTES = 30


def load_env() -> None:
    if not ENV_PATH.is_file():
        return
    for raw_line in ENV_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key or key in os.environ:
            continue
        if value[:1] == value[-1:] and value[:1] in {"'", '"'} and len(value) >= 2:
            value = value[1:-1]
        os.environ[key] = value.replace("\\n", "\n").replace("\\r", "\r")


def env_required(key: str) -> str:
    value = os.environ.get(key, "").strip()
    if not value:
        raise RuntimeError(f"Env obrigatoria ausente: {key}")
    return value


def env_optional(key: str, default: str = "") -> str:
    value = os.environ.get(key, "").strip()
    return value or default


def now_iso() -> str:
    return datetime.now(tz=UTC).isoformat()


def normalize_text(value: str, max_len: int = 0) -> str:
    cleaned = re.sub(r"\s+", " ", str(value or "")).strip()
    return cleaned[:max_len] if max_len else cleaned


def normalize_multiline(value: str, max_len: int = 0) -> str:
    cleaned = str(value or "").replace("\r\n", "\n").replace("\r", "\n")
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
    return cleaned[:max_len] if max_len else cleaned


def build_prompt(context: dict[str, Any], source_name: str) -> str:
    parts = ["Transcreva em portugues do Brasil com pontuacao natural, sem resumir e sem inventar termos."]
    source_hint = normalize_text(Path(source_name).stem, 80)
    if source_hint:
        parts.append(f"Arquivo: {source_hint}.")
    for label, key, max_len in [
        ("Aluno", "student_name", 120),
        ("Profissao", "profession", 120),
        ("Turma", "turma_codigo", 60),
    ]:
        value = normalize_text(str(context.get(key) or ""), max_len)
        if value:
            parts.append(f"{label}: {value}.")
    cidade = normalize_text(str(context.get("cidade") or ""), 80)
    estado = normalize_text(str(context.get("estado") or ""), 12)
    if cidade or estado:
        parts.append(f"Contexto geografico: {' / '.join(item for item in [cidade, estado] if item)}.")
    courses = [normalize_text(str(item), 80) for item in (context.get("courses") or []) if normalize_text(str(item), 80)]
    if courses:
        parts.append(f"Cursos relacionados: {', '.join(courses[:6])}.")
    tags = [normalize_text(str(item), 60) for item in (context.get("tags") or []) if normalize_text(str(item), 60)]
    if tags:
        parts.append(f"Termos relevantes: {', '.join(tags[:8])}.")
    return normalize_text(" ".join(parts), 700)


def extract_folder_id(value: str) -> str:
    raw = value.strip()
    if re.match(r"^[A-Za-z0-9_-]{10,}$", raw):
        return raw
    for pattern in [
        r"(?:^|/)folders/([A-Za-z0-9_-]{10,})",
        r"drive/folders/([A-Za-z0-9_-]{10,})",
        r"[?&]id=([A-Za-z0-9_-]{10,})",
    ]:
        match = re.search(pattern, raw)
        if match:
            return match.group(1)
    return ""


def mime_extension(mime_type: str, name: str) -> str:
    suffix = Path(name).suffix.lower().strip(".")
    if suffix:
        return suffix
    return {
        "audio/mpeg": "mp3",
        "audio/mp4": "m4a",
        "audio/x-m4a": "m4a",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/webm": "webm",
        "audio/ogg": "ogg",
        "audio/flac": "flac",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
    }.get(mime_type.lower().strip(), "bin")


class SupabaseRest:
    def __init__(self, base_url: str, service_key: str):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        })

    def request(self, method: str, path: str, *, params: dict[str, Any] | None = None, body: Any = None, headers: dict[str, str] | None = None) -> Any:
        response = self.session.request(method, f"{self.base_url}{path}", params=params, json=body, headers=headers or {}, timeout=120)
        if response.status_code >= 400:
            raise RuntimeError(f"Supabase {method} {path} falhou: {response.status_code} {response.text[:300]}")
        return response.json() if response.text.strip() else None

    def next_job(self) -> dict[str, Any] | None:
        queued = self.request("GET", "/rest/v1/gp_depoimento_transcription_jobs", params={
            "select": "*",
            "status": "eq.queued",
            "order": "created_at.asc",
            "limit": "1",
        }) or []
        if queued:
            job = queued[0]
            claimed = self.request("PATCH", "/rest/v1/gp_depoimento_transcription_jobs", params={
                "id": f"eq.{job['id']}",
                "status": "eq.queued",
                "select": "*",
            }, headers={"Prefer": "return=representation"}, body={
                "status": "processing",
                "attempt_count": int(job.get("attempt_count") or 0) + 1,
                "started_at": now_iso(),
                "locked_at": now_iso(),
                "error_message": None,
            }) or []
            return claimed[0] if claimed else None

        stale_before = (datetime.now(tz=UTC) - timedelta(minutes=STALE_LOCK_MINUTES)).isoformat()
        stale = self.request("GET", "/rest/v1/gp_depoimento_transcription_jobs", params={
            "select": "*",
            "status": "eq.processing",
            "locked_at": f"lt.{stale_before}",
            "order": "created_at.asc",
            "limit": "1",
        }) or []
        if not stale:
            return None
        job = stale[0]
        reclaimed = self.request("PATCH", "/rest/v1/gp_depoimento_transcription_jobs", params={
            "id": f"eq.{job['id']}",
            "status": "eq.processing",
            "select": "*",
        }, headers={"Prefer": "return=representation"}, body={
            "attempt_count": int(job.get("attempt_count") or 0) + 1,
            "locked_at": now_iso(),
            "error_message": None,
        }) or []
        return reclaimed[0] if reclaimed else None

    def patch_job(self, job_id: str, payload: dict[str, Any]) -> None:
        self.request("PATCH", "/rest/v1/gp_depoimento_transcription_jobs", params={"id": f"eq.{job_id}"}, headers={"Prefer": "return=minimal"}, body=payload)

    def patch_depoimentos(self, job_id: str, payload: dict[str, Any]) -> None:
        self.request("PATCH", "/rest/v1/gp_depoimentos", params={"transcription_job_id": f"eq.{job_id}"}, headers={"Prefer": "return=minimal"}, body=payload)


class DriveClient:
    FOLDER_MIME = "application/vnd.google-apps.folder"

    def __init__(self):
        self.credentials = self._load_credentials()
        self.session = requests.Session()

    def _load_credentials(self):
        raw_json = env_optional("GOOGLE_SERVICE_ACCOUNT_JSON")
        raw_b64 = env_optional("GOOGLE_SERVICE_ACCOUNT_JSON_B64")
        raw_path = env_optional("GOOGLE_SERVICE_ACCOUNT_PATH")
        if raw_b64:
            payload = base64.b64decode(raw_b64).decode("utf-8")
        elif raw_json:
            payload = raw_json
        elif raw_path:
            payload = Path(raw_path).read_text(encoding="utf-8")
        else:
            raise RuntimeError("Google Service Account nao configurada.")
        return service_account.Credentials.from_service_account_info(json.loads(payload), scopes=["https://www.googleapis.com/auth/drive.readonly"])

    def _headers(self) -> dict[str, str]:
        if not self.credentials.valid:
            self.credentials.refresh(GoogleAuthRequest())
        return {"Authorization": f"Bearer {self.credentials.token}"}

    def _list_direct_children(self, folder_id: str, page_token: str = "") -> dict[str, Any]:
        response = self.session.get("https://www.googleapis.com/drive/v3/files", headers=self._headers(), params={
            "q": f"'{folder_id}' in parents and trashed = false",
            "fields": "nextPageToken,files(id,name,mimeType)",
            "pageSize": "1000",
            "supportsAllDrives": "true",
            "includeItemsFromAllDrives": "true",
            "corpora": "allDrives",
            "pageToken": page_token,
        }, timeout=60)
        response.raise_for_status()
        return response.json()

    def list_files(self, folder_id: str) -> list[dict[str, Any]]:
        visited_folders = {folder_id}
        pending = [folder_id]
        files: list[dict[str, Any]] = []

        while pending:
            current_folder = pending.pop(0)
            page_token = ""

            while True:
                payload = self._list_direct_children(current_folder, page_token)
                for item in payload.get("files", []):
                    if str(item.get("mimeType") or "") == self.FOLDER_MIME:
                        child_folder_id = str(item.get("id") or "")
                        if child_folder_id and child_folder_id not in visited_folders:
                            visited_folders.add(child_folder_id)
                            pending.append(child_folder_id)
                        continue
                    files.append(item)

                page_token = str(payload.get("nextPageToken") or "")
                if not page_token:
                    break

        return files

    def download(self, file_id: str, suffix: str) -> Path:
        response = self.session.get(f"https://www.googleapis.com/drive/v3/files/{file_id}", headers=self._headers(), params={"alt": "media", "supportsAllDrives": "true"}, stream=True, timeout=300)
        response.raise_for_status()
        fd, tmp = tempfile.mkstemp(prefix="gp_dep_", suffix=f".{suffix}")
        os.close(fd)
        path = Path(tmp)
        with path.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    handle.write(chunk)
        return path


class LocalTranscriber:
    def __init__(self):
        model_name = env_optional("DEPOIMENTOS_WHISPER_MODEL", "large-v3")
        device = env_optional("DEPOIMENTOS_WHISPER_DEVICE", "auto")
        compute_type = env_optional("DEPOIMENTOS_WHISPER_COMPUTE_TYPE", "int8")
        LOG.info("Carregando modelo %s (%s / %s)", model_name, device, compute_type)
        self.model = WhisperModel(model_name, device=device, compute_type=compute_type)
        self.model_name = model_name

    def transcribe(self, path: Path, context: dict[str, Any], source_name: str) -> dict[str, Any]:
        prompt = build_prompt(context, source_name)
        segments_iter, _ = self.model.transcribe(str(path), language="pt", vad_filter=True, beam_size=5, initial_prompt=prompt or None, temperature=0.0)
        segments = list(segments_iter)
        raw_text = normalize_multiline(" ".join(seg.text.strip() for seg in segments if seg.text), 50000)
        text = normalize_multiline("\n\n".join(normalize_text(seg.text, 4000) for seg in segments if normalize_text(seg.text, 4000)), 50000) or raw_text
        return {"text": text, "raw_text": raw_text, "segments_count": len(segments), "chars": len(text)}


def select_media(files: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str | None]:
    audio_files = [item for item in files if str(item.get("mimeType") or "").startswith("audio/")]
    video_files = [item for item in files if str(item.get("mimeType") or "").startswith("video/")]
    audio_files.sort(key=lambda item: str(item.get("name") or "").lower())
    video_files.sort(key=lambda item: str(item.get("name") or "").lower())
    video_url = f"https://drive.google.com/file/d/{video_files[0]['id']}/view" if video_files else None
    return audio_files, video_files, video_url


def process_job(job: dict[str, Any], supabase: SupabaseRest, drive: DriveClient, transcriber: LocalTranscriber) -> None:
    job_id = str(job["id"])
    folder_id = extract_folder_id(str(job.get("folder_id") or job.get("folder_url") or ""))
    if not folder_id:
        raise RuntimeError("Job sem folder_id valido.")

    prompt_context = job.get("prompt_context") if isinstance(job.get("prompt_context"), dict) else {}
    files = drive.list_files(folder_id)
    audio_files, video_files, video_url = select_media(files)
    targets = audio_files if audio_files else video_files[:1]
    if not targets:
        raise RuntimeError("Nenhum arquivo de audio ou video encontrado na pasta.")

    warnings = []
    if not audio_files and video_files:
        warnings.append("Nenhum audio dedicado encontrado; transcricao feita a partir do primeiro video.")

    transcript_parts = []
    raw_parts = []
    succeeded = 0
    failed = 0
    total_segments = 0
    for media in targets:
        temp_path: Path | None = None
        try:
            mime_type = str(media.get("mimeType") or "")
            temp_path = drive.download(str(media["id"]), mime_extension(mime_type, str(media.get("name") or "midia")))
            result = transcriber.transcribe(temp_path, prompt_context, str(media.get("name") or "midia"))
            transcript_parts.append(result["text"])
            raw_parts.append(result["raw_text"])
            succeeded += 1
            total_segments += int(result["segments_count"])
            supabase.patch_job(job_id, {"locked_at": now_iso()})
        except Exception as exc:
            failed += 1
            warnings.append(normalize_text(f"Falha ao processar {media.get('name')}: {exc}", 240))
        finally:
            if temp_path and temp_path.is_file():
                temp_path.unlink(missing_ok=True)

    if succeeded == 0:
        raise RuntimeError(warnings[0] if warnings else "Nenhuma midia foi transcrita com sucesso.")

    transcript = normalize_multiline("\n\n".join(transcript_parts), 50000)
    transcript_raw = normalize_multiline("\n\n".join(raw_parts), 50000)
    notes = normalize_multiline("\n".join([
        "Origem: worker local faster-whisper.",
        f"Arquivos de audio na pasta: {len(audio_files)}.",
        f"Midias transcritas com sucesso: {succeeded}.",
        f"Midias com falha: {failed}.",
        f"Segmentos detectados: {total_segments}.",
        "Primeiro video localizado automaticamente." if video_url else "",
        ("Avisos: " + " ".join(warnings)) if warnings else "",
    ]), 4000)

    supabase.patch_job(job_id, {
        "status": "completed",
        "provider": "faster-whisper",
        "video_url": video_url,
        "transcript": transcript,
        "transcript_raw": transcript_raw,
        "source_audios_count": len(audio_files),
        "audios_succeeded": succeeded,
        "audios_failed": failed,
        "processing_notes": notes,
        "warnings": warnings,
        "error_message": None,
        "completed_at": now_iso(),
        "locked_at": None,
    })
    supabase.patch_depoimentos(job_id, {
        "video_url": video_url,
        "transcript": transcript,
        "source_audios_count": len(audio_files),
        "processing_notes": notes,
    })


def fail_job(supabase: SupabaseRest, job_id: str, exc: Exception) -> None:
    supabase.patch_job(job_id, {
        "status": "failed",
        "error_message": normalize_text(str(exc) or "Falha tecnica na transcricao.", 240),
        "completed_at": now_iso(),
        "locked_at": None,
    })


def run_once(supabase: SupabaseRest, drive: DriveClient, transcriber: LocalTranscriber) -> bool:
    job = supabase.next_job()
    if not job:
        return False
    job_id = str(job["id"])
    LOG.info("Processando job %s", job_id)
    try:
        process_job(job, supabase, drive, transcriber)
        LOG.info("Job %s concluido", job_id)
    except Exception as exc:
        LOG.exception("Job %s falhou: %s", job_id, exc)
        fail_job(supabase, job_id, exc)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--interval", type=int, default=15)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    if not args.once and not args.watch:
        parser.error("Use --once ou --watch.")

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)-8s %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    load_env()

    supabase = SupabaseRest(env_required("SUPABASE_URL"), env_required("SUPABASE_SERVICE_ROLE_KEY"))
    drive = DriveClient()
    transcriber = LocalTranscriber()

    if args.once:
        run_once(supabase, drive, transcriber)
        return 0

    while True:
        if not run_once(supabase, drive, transcriber):
            time.sleep(max(3, args.interval))


if __name__ == "__main__":
    sys.exit(main())
