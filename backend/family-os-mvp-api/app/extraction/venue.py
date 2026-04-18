"""
Optional venue resolution layer.

The LLM must never overwrite `locationRaw`. A resolver may suggest normalized name / address
for UI or future MapKit/Apple Maps / Mapbox integration.

Hook: implement `VenueResolver.resolve(raw: str) -> VenueCandidate | None`.
Default `NoopVenueResolver` returns low-confidence unresolved so the client keeps raw text.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from ..schemas_extraction import VenueCandidate


class VenueResolver(ABC):
    """Pluggable geocoding / place-name normalization."""

    @abstractmethod
    def resolve(self, location_raw: str) -> Optional[VenueCandidate]:
        ...


class NoopVenueResolver(VenueResolver):
    """Preserves raw text; does not call external APIs."""

    def resolve(self, location_raw: str) -> Optional[VenueCandidate]:
        text = (location_raw or "").strip()
        if not text:
            return None
        return VenueCandidate(
            rawQuery=text,
            normalizedName=None,
            formattedAddress=None,
            latitude=None,
            longitude=None,
            confidence=0.0,
            unresolved=True,
        )


def apply_venue_resolution(
    location_raw: str,
    resolver: VenueResolver,
) -> Optional[VenueCandidate]:
    return resolver.resolve(location_raw)
