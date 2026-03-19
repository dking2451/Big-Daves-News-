from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from .ai_client import extract_events_with_ai
from .extractor import normalize_candidates
from .schemas import ErrorEnvelope, ExtractionRequest, ExtractionResponse, UploadResponse

app = FastAPI(title="Family OS MVP API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path("/tmp/family_os_mvp_uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post(
    "/v1/upload-image",
    response_model=UploadResponse,
    responses={500: {"model": ErrorEnvelope}},
)
async def upload_image(file: UploadFile = File(...)) -> UploadResponse:
    try:
        upload_id = str(uuid4())
        suffix = Path(file.filename or "upload.jpg").suffix or ".jpg"
        target = UPLOAD_DIR / f"{upload_id}{suffix}"
        content = await file.read()
        target.write_bytes(content)
        return UploadResponse(
            uploadId=upload_id,
            filename=file.filename or "upload.jpg",
            contentType=file.content_type or "application/octet-stream",
            sizeBytes=len(content),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": {"code": "UPLOAD_FAILED", "message": str(exc)}},
        ) from exc


@app.post(
    "/v1/extract-events",
    response_model=ExtractionResponse,
    responses={500: {"model": ErrorEnvelope}},
)
async def extract_events(payload: ExtractionRequest) -> ExtractionResponse:
    try:
        ai_result = extract_events_with_ai(payload.ocrText, payload.sourceHint)
        candidates = normalize_candidates(ai_result.get("candidates", []))
        return ExtractionResponse(candidates=candidates)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "code": "EXTRACTION_FAILED",
                    "message": "Could not extract events from provided text.",
                    "details": str(exc),
                }
            },
        ) from exc
