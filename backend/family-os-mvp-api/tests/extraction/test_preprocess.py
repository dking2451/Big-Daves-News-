from app.extraction.preprocess import preprocess_ocr


def test_preprocess_numbered_lines_skip_empty():
    doc = preprocess_ocr("Line A\n\nLine B")
    assert [ln.id for ln in doc.lines] == ["L0", "L1"]
    assert doc.lines[0].text == "Line A"


def test_preprocess_single_blob():
    doc = preprocess_ocr("only one")
    assert len(doc.lines) == 1
    assert doc.lines[0].id == "L0"
