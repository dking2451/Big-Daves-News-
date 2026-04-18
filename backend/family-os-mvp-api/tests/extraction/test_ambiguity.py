from app.extraction.ambiguity import apply_ambiguity_rules


def test_vague_time_adds_unresolved():
    ev = apply_ambiguity_rules(
        {
            "title": "Movie",
            "timeQualifier": "vague",
            "startTime": None,
            "evidence": [],
        }
    )
    assert "startTime" in ev["unresolvedFields"]
    assert any("vague" in r.lower() for r in ev["ambiguityReasons"])


def test_conflict_in_evidence():
    ev = apply_ambiguity_rules(
        {
            "title": "Game",
            "evidence": [{"field": "startTime", "binding": "conflicting", "lineIds": ["L1"]}],
        }
    )
    assert "startTime" in ev["unresolvedFields"] or "time" in str(ev["unresolvedFields"])
