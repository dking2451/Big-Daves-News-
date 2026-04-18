"""Stage E: merge model hints with deterministic ambiguity rules."""

from __future__ import annotations

from typing import Any, Dict, List, Set

from ..schemas_extraction import FieldBinding, FieldEvidence


def _binding(s: str) -> FieldBinding:
    try:
        return FieldBinding(s)
    except ValueError:
        return FieldBinding.explicit


def apply_ambiguity_rules(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich inferredFields / unresolvedFields / ambiguityReasons without inventing data.
    Operates on plain dict before Pydantic validation.
    """
    inferred: Set[str] = set(event.get("inferredFields") or [])
    unresolved: Set[str] = set(event.get("unresolvedFields") or [])
    reasons: List[str] = list(event.get("ambiguityReasons") or [])

    tq = str(event.get("timeQualifier") or "").lower()
    if tq in ("vague", "approximate", "unknown"):
        if "startTime" not in unresolved and not event.get("startTime"):
            unresolved.add("startTime")
        if "vague_time" not in [r.lower() for r in reasons]:
            reasons.append("Time wording is vague or approximate in source.")

    lq = str(event.get("locationQualifier") or "").lower()
    if lq in ("partial", "unknown"):
        unresolved.add("locationRaw")
        reasons.append("Location text is partial or ambiguous.")

    ev: List[Dict[str, Any]] = event.get("evidence") or []
    for row in ev:
        b = _binding(str(row.get("binding") or "explicit"))
        field = str(row.get("field") or "")
        if b == FieldBinding.conflicting:
            reasons.append(f"Conflicting source signals for {field or 'field'}.")
            unresolved.add(field or "time")
        elif b == FieldBinding.inferred and field:
            inferred.add(field)
        elif b == FieldBinding.unresolved and field:
            unresolved.add(field)

    rec = event.get("recurrence") or {}
    rk = str(rec.get("kind") or "unknown")
    if rk not in ("single", "unknown") and not event.get("date"):
        reasons.append("Recurrence pattern without a single anchored calendar date.")
        unresolved.add("date")

    event["inferredFields"] = sorted(inferred)
    event["unresolvedFields"] = sorted(unresolved)
    event["ambiguityReasons"] = reasons
    return event


def evidence_dicts_to_models(rows: List[Dict[str, Any]]) -> List[FieldEvidence]:
    out: List[FieldEvidence] = []
    for row in rows:
        try:
            out.append(
                FieldEvidence(
                    field=str(row.get("field") or ""),
                    text=str(row.get("text") or ""),
                    lineIds=[str(x) for x in (row.get("lineIds") or [])],
                    binding=_binding(str(row.get("binding") or "explicit")),
                )
            )
        except Exception:
            continue
    return out
