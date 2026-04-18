"""Pipeline integration with mocked LLM stages (no OpenAI)."""

from unittest.mock import patch

from app.schemas import ExtractionRequest

STAGE1 = {
    "chunks": [],
    "eventSegments": [{"segmentId": "E1", "lineIds": ["L0"], "segmentKind": "single_event", "boundaryNote": ""}],
    "nonEvents": [{"kind": "registration_deadline", "lineIds": ["L2"], "summary": "Register by 3/15"}],
    "documentNotes": ["test doc"],
}

STAGE2 = {
    "events": [
        {
            "segmentId": "E1",
            "title": "Open Gym",
            "childName": "",
            "childNeedsAssignment": True,
            "category": "sports",
            "date": "2026-04-04",
            "endDate": None,
            "startTime": "18:30",
            "endTime": "21:00",
            "timeQualifier": "explicit",
            "locationRaw": "East Cardinal MS Gym",
            "locationQualifier": "partial",
            "notes": "$5 cash, Ages 13–18",
            "organizerContact": "",
            "recurrence": {
                "kind": "recurrence_pattern",
                "humanReadable": "Fridays",
                "extraDates": [],
            },
            "evidence": [{"field": "title", "text": "Open Gym", "lineIds": ["L0"], "binding": "explicit"}],
            "inferredFields": [],
            "unresolvedFields": [],
            "ambiguityReasons": [],
            "modelConfidence": 0.75,
            "ambiguityFlag": False,
            "sourceType": "flyer",
        }
    ],
    "nonEvents": [],
}


def test_run_pipeline_mocked():
    from app.extraction.pipeline import run_pipeline

    with patch("app.extraction.pipeline.run_stage1", return_value=STAGE1), patch(
        "app.extraction.pipeline.run_stage2", return_value=STAGE2
    ):
        req = ExtractionRequest(ocrText="Fridays 6:30–9 PM\nEast Cardinal MS Gym", sourceHint="test")
        resp = run_pipeline(req)

    assert resp.extractionVersion == "2"
    assert len(resp.candidates) == 1
    assert resp.candidates[0].title == "Open Gym"
    assert resp.candidates[0].location == "East Cardinal MS Gym"
    assert resp.events is not None and len(resp.events) == 1
    assert resp.events[0].locationRaw == "East Cardinal MS Gym"
    assert resp.nonEventCandidates  # from stage1 fallback
    assert resp.review is not None
    assert resp.pipelineTrace is not None
