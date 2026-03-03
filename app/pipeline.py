from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from html import unescape
from typing import Dict, List

import feedparser

from app.models import Article, Claim, ClaimEvidence, SourceConfig


def fetch_articles(sources: List[SourceConfig], per_source_limit: int = 10) -> List[Article]:
    articles: List[Article] = []
    for source in sources:
        parsed = feedparser.parse(source.rss)
        for entry in parsed.entries[:per_source_limit]:
            published_at = _parse_datetime(getattr(entry, "published", None))
            articles.append(
                Article(
                    source_name=source.name,
                    title=getattr(entry, "title", "").strip(),
                    url=getattr(entry, "link", "").strip(),
                    summary=getattr(entry, "summary", "").strip(),
                    image_url=extract_entry_image_url(entry),
                    published_at=published_at,
                )
            )
    return articles


def extract_claim_candidates(article: Article) -> List[str]:
    claims: List[str] = []
    seen_keys: List[str] = []

    # Prefer the headline as the primary claim when it is descriptive enough.
    title_claim = normalize_claim(strip_html(article.title))
    if len(title_claim) >= 25 and looks_fact_like(title_claim):
        claims.append(title_claim)
        seen_keys.append(_dedupe_key(title_claim))

    sentences = split_sentences(strip_html(article.summary))
    for sentence in sentences:
        cleaned = sentence.strip()
        if len(cleaned) < 35:
            continue
        if not looks_fact_like(cleaned):
            continue
        normalized = normalize_claim(cleaned)
        dedupe_key = _dedupe_key(normalized)
        if not dedupe_key:
            continue
        if any(_is_similar_claim_key(dedupe_key, key) for key in seen_keys):
            continue
        claims.append(normalized)
        seen_keys.append(dedupe_key)

    return claims[:5]


def validate_claims(
    articles: List[Article],
    source_index: Dict[str, SourceConfig],
    min_tier1_sources: int = 2,
) -> List[Claim]:
    claim_map: Dict[str, Claim] = {}

    for article in articles:
        source = source_index[article.source_name]
        for claim_text in extract_claim_candidates(article):
            claim_id = claim_hash(claim_text)
            existing = claim_map.get(claim_id)
            if not existing:
                category = categorize_claim(claim_text, preferred_topic=source.topic)
                existing = Claim(
                    claim_id=claim_id,
                    text=claim_text,
                    category=category,
                    subtopic=categorize_subtopic(claim_text, category),
                    image_url=article.image_url,
                    first_seen=article.published_at or datetime.utcnow(),
                )
                claim_map[claim_id] = existing
            elif not existing.image_url and article.image_url:
                existing.image_url = article.image_url

            evidence = ClaimEvidence(
                source_name=article.source_name,
                source_tier=source.tier,
                source_trust_score=source.trust_score,
                article_title=article.title,
                article_url=article.url,
                published_at=article.published_at,
            )
            existing.evidence.append(evidence)

    for claim in claim_map.values():
        _score_claim(claim, min_tier1_sources=min_tier1_sources)

    ranked = sorted(
        claim_map.values(),
        key=lambda c: (
            recency_rank(c.first_seen),
            confidence_rank(c.confidence),
            len(c.evidence),
        ),
        reverse=True,
    )
    return ranked


def _score_claim(claim: Claim, min_tier1_sources: int) -> None:
    source_count = len({e.source_name for e in claim.evidence})
    tier1_sources = {e.source_name for e in claim.evidence if e.source_tier == 1}
    if len(tier1_sources) >= min_tier1_sources:
        claim.status = "validated"
        claim.confidence = "High"
    elif len(tier1_sources) >= 1 and source_count >= 2:
        claim.status = "validated"
        claim.confidence = "Medium"
    else:
        avg_trust = sum(e.source_trust_score for e in claim.evidence) / max(len(claim.evidence), 1)
        if avg_trust >= 0.9 and source_count >= 2:
            claim.status = "validated"
            claim.confidence = "Medium"
        else:
            claim.status = "unconfirmed"
            claim.confidence = "Medium" if len(tier1_sources) >= 1 else "Low"


def categorize_claim(text: str, preferred_topic: str | None = None) -> str:
    lower = text.lower()
    topic = (preferred_topic or "").strip().lower()

    # Respect trusted source-topic routing so sports/business feeds don't drift into world.
    if topic == "sports":
        return "Sports"
    if topic == "business":
        return "Business"
    if topic == "politics":
        return "Politics"
    if topic == "ai":
        if re.search(r"\b(telecom|telecommunications|telco|carrier|5g|6g|wireless|broadband)\b", lower):
            return "AI in Telecom"
        return "AI"

    category_patterns = [
        (
            "AI in Telecom",
            [
                r"\b(ai|artificial intelligence)\b.*\b(telecom|telecommunications|telco|carrier|5g|6g|wireless|broadband)\b",
                r"\b(telecom|telecommunications|telco|carrier|5g|6g|wireless|broadband)\b.*\b(ai|artificial intelligence|machine learning|generative ai|genai)\b",
            ],
        ),
        (
            "AI",
            [
                r"\bai\b",
                r"\bartificial intelligence\b",
                r"\bmachine learning\b",
                r"\bgenerative ai\b",
                r"\bgenai\b",
                r"\bllm\b",
                r"\bopenai\b",
                r"\bchatgpt\b",
                r"\bmodel\b",
                r"\bneural\b",
                r"\bdeep learning\b",
            ],
        ),
        (
            "Business",
            [
                r"\bbusiness\b",
                r"\beconomy\b",
                r"\beconomic\b",
                r"\bmarket\b",
                r"\bstock\b",
                r"\bstocks\b",
                r"\bearnings\b",
                r"\brevenue\b",
                r"\bprofit\b",
                r"\bcompany\b",
                r"\bcompanies\b",
                r"\binvestment\b",
                r"\bbank\b",
                r"\bfinance\b",
                r"\bfinancial\b",
                r"\binflation\b",
            ],
        ),
        (
            "Sports",
            [
                r"\bnfl\b",
                r"\bcollege football\b",
                r"\bncaa football\b",
                r"\bncaaf\b",
                r"\bsuper bowl\b",
                r"\bquarterback\b",
                r"\blinebacker\b",
                r"\bf1\b",
                r"\bformula 1\b",
                r"\bgrand prix\b",
                r"\bgp\b",
                r"\bsprint race\b",
                r"\bdrag racing\b",
                r"\bnhra\b",
                r"\btop fuel\b",
                r"\bfunny car\b",
                r"\bpro stock\b",
                r"\bnba\b",
                r"\bbasketball\b",
                r"\bnhl\b",
                r"\bhockey\b",
            ],
        ),
        (
            "Politics",
            [
                r"\bpresident\b",
                r"\bcongress\b",
                r"\bsenate\b",
                r"\bhouse\b",
                r"\bwhite house\b",
                r"\bgovernment\b",
                r"\belection\b",
                r"\bcampaign\b",
                r"\bpolicy\b",
                r"\blegislation\b",
            ],
        ),
        (
            "US News",
            [
                r"\bu\.?s\.?\b",
                r"\bunited states\b",
                r"\bamerica\b",
                r"\btexas\b",
                r"\bcalifornia\b",
                r"\bnew york\b",
                r"\bwashington\b",
            ],
        ),
        (
            "World News",
            [
                r"\bworld\b",
                r"\binternational\b",
                r"\beurope\b",
                r"\basia\b",
                r"\bmiddle east\b",
                r"\bafrica\b",
                r"\bukraine\b",
                r"\bchina\b",
                r"\brussia\b",
            ],
        ),
    ]

    for category, patterns in category_patterns:
        if any(re.search(pattern, lower) for pattern in patterns):
            return category
    return "World News"


def categorize_subtopic(text: str, category: str) -> str:
    lower = text.lower()
    subtopic_patterns = {
        "World News": [
            ("Conflict", [r"\bwar\b", r"\bconflict\b", r"\bmilitary\b", r"\bstrike\b", r"\bceasefire\b"]),
            ("Diplomacy", [r"\bdiplomatic\b", r"\bsummit\b", r"\btalks\b", r"\btreaty\b", r"\bsanctions\b"]),
            ("Energy", [r"\boil\b", r"\bgas\b", r"\benergy\b", r"\bpipeline\b", r"\bpower\b"]),
            ("Migration", [r"\bmigration\b", r"\brefugee\b", r"\bborder\b", r"\bdisplaced\b"]),
            ("Trade", [r"\btrade\b", r"\btariff\b", r"\bexport\b", r"\bimport\b", r"\bsupply chain\b"]),
        ],
        "US News": [
            ("Policy", [r"\bpolicy\b", r"\bcongress\b", r"\bsenate\b", r"\bhouse\b", r"\bgovernment\b"]),
            ("Economy", [r"\beconomy\b", r"\binflation\b", r"\brates\b", r"\bjobs\b", r"\bmarket\b"]),
            ("Public Safety", [r"\bpolice\b", r"\bcourt\b", r"\bcrime\b", r"\binvestigation\b", r"\bstorm\b", r"\bfire\b", r"\bemergency\b"]),
            ("Health", [r"\bhealth\b", r"\bhospital\b", r"\bdisease\b", r"\bmedical\b", r"\bcdc\b"]),
            ("Education", [r"\bschool\b", r"\buniversity\b", r"\bcollege\b", r"\beducation\b", r"\bcampus\b"]),
            ("Immigration", [r"\bimmigration\b", r"\bborder\b", r"\bmigrant\b", r"\bvisa\b", r"\basylum\b"]),
            ("Weather", [r"\bhurricane\b", r"\bflood\b", r"\btornado\b", r"\bweather\b", r"\bstorm\b", r"\bwildfire\b"]),
        ],
        "Politics": [
            ("Elections", [r"\belection\b", r"\bcampaign\b", r"\bvote\b", r"\bpoll\b", r"\bcandidate\b"]),
            ("Congress", [r"\bcongress\b", r"\bsenate\b", r"\bhouse\b", r"\bbill\b", r"\bhearing\b"]),
            ("White House", [r"\bwhite house\b", r"\bpresident\b", r"\badministration\b"]),
            ("Courts", [r"\bcourt\b", r"\bjudge\b", r"\bruling\b", r"\bsupreme court\b"]),
            ("Foreign Policy", [r"\bdiplomatic\b", r"\bsanctions\b", r"\ballies\b", r"\bdefense\b"]),
        ],
        "Business": [
            ("Markets", [r"\bmarket\b", r"\bstocks?\b", r"\bshares\b", r"\btrading\b"]),
            ("Earnings", [r"\bearnings\b", r"\brevenue\b", r"\bprofit\b", r"\bquarter\b"]),
            ("Macro", [r"\binflation\b", r"\brates\b", r"\bgdp\b", r"\beconomy\b"]),
            ("Banking", [r"\bbank\b", r"\blending\b", r"\bcredit\b", r"\bfed\b"]),
            ("Deals", [r"\bacquire\b", r"\bmerger\b", r"\bdeal\b", r"\bbuyout\b"]),
        ],
        "AI": [
            ("Models", [r"\bmodel\b", r"\bllm\b", r"\bopenai\b", r"\banthropic\b", r"\bgemini\b"]),
            ("Regulation", [r"\bregulation\b", r"\brules\b", r"\bpolicy\b", r"\bsafety\b", r"\bgovernance\b"]),
            ("Products", [r"\blaunch\b", r"\bfeature\b", r"\bassistant\b", r"\bcopilot\b"]),
            ("Chips", [r"\bchip\b", r"\bgpu\b", r"\bnvidia\b", r"\bsemiconductor\b"]),
            ("Enterprise AI", [r"\benterprise\b", r"\bworkflow\b", r"\bautomation\b", r"\bproductivity\b"]),
        ],
        "AI in Telecom": [
            ("Network Automation", [r"\bnetwork\b", r"\bautomation\b", r"\boptimization\b", r"\boperations\b"]),
            ("5G/6G", [r"\b5g\b", r"\b6g\b", r"\bwireless\b", r"\bspectrum\b"]),
            ("Carrier AI", [r"\bcarrier\b", r"\btelecom\b", r"\btelco\b", r"\bbroadband\b"]),
            ("Customer AI", [r"\bcustomer\b", r"\bsupport\b", r"\bchatbot\b", r"\bservice\b"]),
            ("Edge AI", [r"\bedge\b", r"\blatency\b", r"\binference\b", r"\breal-time\b"]),
        ],
        "Sports": [
            ("NFL", [r"\bnfl\b", r"\bfootball\b", r"\bquarterback\b", r"\bsuper bowl\b"]),
            ("College Football", [r"\bcollege football\b", r"\bncaa\b", r"\bncaaf\b"]),
            ("F1", [r"\bf1\b", r"\bformula 1\b", r"\bgrand prix\b"]),
            ("Drag Racing", [r"\bdrag racing\b", r"\bnhra\b", r"\btop fuel\b", r"\bfunny car\b"]),
            ("NBA/NHL", [r"\bnba\b", r"\bbasketball\b", r"\bnhl\b", r"\bhockey\b"]),
        ],
    }
    for subtopic, patterns in subtopic_patterns.get(category, []):
        if any(re.search(pattern, lower) for pattern in patterns):
            return subtopic
    fallback_by_category = {
        "US News": "Top Stories",
        "World News": "Global Brief",
        "Politics": "Policy Watch",
        "Business": "Market Watch",
        "AI": "AI Brief",
        "AI in Telecom": "Telecom AI Brief",
        "Sports": "Game Day",
    }
    return fallback_by_category.get(category, "General")


def confidence_rank(label: str) -> int:
    return {"Low": 1, "Medium": 2, "High": 3}.get(label, 0)


def recency_rank(value: datetime | None) -> float:
    if value is None:
        return 0.0
    if value.tzinfo is None:
        # Treat naive datetimes as UTC so ordering is stable.
        value = value.replace(tzinfo=timezone.utc)
    return value.timestamp()


def claim_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def normalize_claim(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text


def strip_html(text: str) -> str:
    return re.sub(r"<[^>]+>", " ", text or "")


def split_sentences(text: str) -> List[str]:
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]


def _dedupe_key(text: str) -> str:
    normalized = re.sub(r"[^\w\s]", " ", text.lower())
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def _is_similar_claim_key(left: str, right: str) -> bool:
    if left == right:
        return True
    if left in right or right in left:
        return True

    left_tokens = set(left.split())
    right_tokens = set(right.split())
    if not left_tokens or not right_tokens:
        return False

    overlap_ratio = len(left_tokens & right_tokens) / max(len(left_tokens), len(right_tokens))
    return overlap_ratio >= 0.85


def looks_fact_like(sentence: str) -> bool:
    indicators = [
        r"\b\d{1,4}\b",
        r"\bsaid\b",
        r"\breported\b",
        r"\bannounced\b",
        r"\baccording to\b",
        r"\bconfirmed\b",
        r"\bwill\b",
        r"\bhas\b",
        r"\bhave\b",
    ]
    return any(re.search(pattern, sentence, flags=re.IGNORECASE) for pattern in indicators)


def _parse_datetime(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return parsedate_to_datetime(raw)
    except (TypeError, ValueError):
        return None


def extract_entry_image_url(entry) -> str | None:
    # Common RSS media payload styles.
    media_content = getattr(entry, "media_content", None) or []
    for item in media_content:
        candidate = str(item.get("url", "")).strip()
        if candidate:
            return candidate

    media_thumbnail = getattr(entry, "media_thumbnail", None) or []
    for item in media_thumbnail:
        candidate = str(item.get("url", "")).strip()
        if candidate:
            return candidate

    image_obj = getattr(entry, "image", None)
    if isinstance(image_obj, dict):
        candidate = str(image_obj.get("href", "")).strip() or str(image_obj.get("url", "")).strip()
        if candidate:
            return candidate

    enclosures = getattr(entry, "enclosures", None) or []
    for enclosure in enclosures:
        href = str(enclosure.get("href", "")).strip()
        mime_type = str(enclosure.get("type", "")).strip().lower()
        if href and mime_type.startswith("image/"):
            return href

    links = getattr(entry, "links", None) or []
    for link in links:
        href = str(link.get("href", "")).strip()
        rel = str(link.get("rel", "")).strip().lower()
        mime_type = str(link.get("type", "")).strip().lower()
        if href and rel == "enclosure" and mime_type.startswith("image/"):
            return href

    # Fallback: scrape first image from HTML summary/content.
    html_candidates: list[str] = []
    summary = getattr(entry, "summary", None)
    if isinstance(summary, str) and summary:
        html_candidates.append(summary)
    content_items = getattr(entry, "content", None) or []
    for item in content_items:
        value = item.get("value", "") if isinstance(item, dict) else ""
        if isinstance(value, str) and value:
            html_candidates.append(value)
    for html in html_candidates:
        match = re.search(r"""<img[^>]+src=["']([^"']+)["']""", html, flags=re.IGNORECASE)
        if match:
            return unescape(match.group(1).strip())
    return None
