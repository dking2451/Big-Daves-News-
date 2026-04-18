from app.extraction.compatibility import _expand_multi_date_events


def test_expand_extra_dates_into_rows():
    raw = [
        {
            "title": "Tryouts",
            "date": None,
            "recurrence": {"kind": "two_specific_dates", "extraDates": ["2026-04-06", "2026-04-08"]},
        }
    ]
    out = _expand_multi_date_events(raw)
    assert len(out) == 2
    assert {o["date"] for o in out} == {"2026-04-06", "2026-04-08"}
