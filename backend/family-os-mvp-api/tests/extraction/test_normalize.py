from app.extraction.normalize import normalize_candidates, normalize_time_to_hhmm


def test_normalize_time_12h():
    assert normalize_time_to_hhmm("6:30 PM") == "18:30"
    assert normalize_time_to_hhmm("12:00 AM") == "00:00"


def test_legacy_candidate_location_and_ambiguity():
    raw = [
        {
            "title": "Soccer",
            "category": "sports",
            "date": "2026-04-06",
            "startTime": "18:00",
            "endTime": None,
            "location": "Field 1",
            "notes": "",
            "confidence": 0.8,
            "ambiguityFlag": False,
            "childName": "",
            "childNeedsAssignment": True,
        }
    ]
    out = normalize_candidates(raw)
    assert len(out) == 1
    assert out[0].location == "Field 1"
    assert out[0].ambiguityFlag is False
