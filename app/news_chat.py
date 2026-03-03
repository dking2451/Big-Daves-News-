from __future__ import annotations

import math
import os
import re
from typing import Iterable

import httpx

from app.models import Article, Claim
from app.substack import SubstackPost


def build_news_context(
    question: str,
    claims: list[Claim],
    posts: list[SubstackPost],
    articles: list[Article],
    max_items: int = 30,
) -> str:
    """Build query-focused context so niche topics (e.g., Formula 1) surface reliably."""
    context, _confidence = build_news_context_with_confidence(
        question=question,
        claims=claims,
        posts=posts,
        articles=articles,
        max_items=max_items,
    )
    return context


def build_news_context_with_confidence(
    question: str,
    claims: list[Claim],
    posts: list[SubstackPost],
    articles: list[Article],
    max_items: int = 30,
) -> tuple[str, float]:
    question_words = expanded_question_keywords(question)
    question_ngrams = char_ngrams(question)
    scored: list[tuple[float, str]] = []

    for claim in claims:
        lexical = overlap_score(question_words, _keywords(claim.text))
        semantic = ngram_similarity(question_ngrams, char_ngrams(claim.text))
        score = lexical + (semantic * 3.0)
        if score > 0:
            scored.append((score + 4.0, f"- [Claim|{claim.category}] {claim.text}"))

    for article in articles:
        text = f"{article.title} {article.summary}"
        lexical = overlap_score(question_words, _keywords(text))
        semantic = ngram_similarity(question_ngrams, char_ngrams(text))
        score = lexical + (semantic * 3.0)
        if score > 0:
            scored.append((score + 2.0, f"- [Headline|{article.source_name}] {article.title} ({article.url})"))

    for post in posts:
        lexical = overlap_score(question_words, _keywords(post.title))
        semantic = ngram_similarity(question_ngrams, char_ngrams(post.title))
        score = lexical + (semantic * 2.0)
        if score > 0:
            scored.append((score + 1.0, f"- [Substack|{post.publication}] {post.title} ({post.url})"))

    if not scored:
        # Fallback to broad context when the query is very specific.
        for claim in claims[: max_items // 2]:
            scored.append((1.0, f"- [Claim|{claim.category}] {claim.text}"))
        for article in articles[: max_items // 3]:
            scored.append((1.0, f"- [Headline|{article.source_name}] {article.title} ({article.url})"))
        for post in posts[: max_items // 6]:
            scored.append((1.0, f"- [Substack|{post.publication}] {post.title} ({post.url})"))

    lines = [line for _, line in sorted(scored, reverse=True)[:max_items]]
    top_score = max((score for score, _line in scored), default=0.0)
    confidence = min(1.0, top_score / 10.0)
    return "\n".join(lines), confidence


def ask_talk_to_news_llm(question: str, context: str) -> str:
    base_url = os.getenv("FREE_LLM_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = os.getenv("FREE_LLM_MODEL", "llama3.2:3b")
    timeout_s = float(os.getenv("FREE_LLM_TIMEOUT_SECONDS", "25"))

    system_prompt = (
        "You are a concise news assistant. Use only the provided context. "
        "If context does not contain the answer, say that clearly."
    )
    user_prompt = f"Context:\n{context}\n\nQuestion:\n{question}\n\nAnswer with 3-6 concise bullet points."

    payload = {
        "model": model,
        "stream": False,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }

    with httpx.Client(timeout=timeout_s) as client:
        response = client.post(f"{base_url}/api/chat", json=payload)
        response.raise_for_status()
        body = response.json()
        message = body.get("message", {})
        content = (message.get("content") or "").strip()
        if content:
            return content
    raise RuntimeError("LLM returned an empty response.")


def fallback_news_answer(
    question: str,
    claims: list[Claim],
    posts: list[SubstackPost],
    articles: list[Article],
) -> str:
    question_words = expanded_question_keywords(question)
    question_ngrams = char_ngrams(question)
    scored: list[tuple[int, str]] = []

    for claim in claims:
        score = overlap_score(question_words, _keywords(claim.text)) + int(
            ngram_similarity(question_ngrams, char_ngrams(claim.text)) * 3
        )
        if score > 0:
            scored.append((score, f"- {claim.text} [{claim.category}]"))
    for article in articles:
        score = overlap_score(question_words, _keywords(f"{article.title} {article.summary}")) + int(
            ngram_similarity(question_ngrams, char_ngrams(f"{article.title} {article.summary}")) * 3
        )
        if score > 0:
            scored.append((score, f"- {article.title} [Source: {article.source_name}]"))
    for post in posts:
        score = overlap_score(question_words, _keywords(post.title)) + int(
            ngram_similarity(question_ngrams, char_ngrams(post.title)) * 2
        )
        if score > 0:
            scored.append((score, f"- {post.title} [Substack: {post.publication}]"))

    if not scored:
        return (
            "I could not find a close match in today's pulled headlines. "
            "Try asking with specific names, companies, countries, or topics."
        )

    top_lines = [line for _, line in sorted(scored, reverse=True)[:6]]
    return "I could not reach the free local LLM, but here are the closest relevant headlines:\n\n" + "\n".join(top_lines)


def _keywords(text: str) -> list[str]:
    return re.findall(r"[a-zA-Z]{3,}", text.lower())


def expanded_question_keywords(question: str) -> set[str]:
    words = set(_keywords(question))
    aliases = {
        "formula": {"f1", "formula", "grand", "prix"},
        "f1": {"formula", "grand", "prix"},
        "grand": {"prix", "formula", "f1"},
        "prix": {"grand", "formula", "f1"},
        "nfl": {"football", "quarterback"},
        "football": {"nfl", "college"},
        "college": {"football", "ncaa"},
        "nba": {"basketball"},
        "basketball": {"nba"},
        "hockey": {"nhl"},
        "nhl": {"hockey"},
        "drag": {"racing", "nhra"},
        "racing": {"drag", "f1", "formula", "nhra"},
        "telecom": {"carrier", "wireless", "broadband"},
        "ai": {"artificial", "intelligence", "llm"},
        "business": {"economy", "market", "finance", "company"},
        "economy": {"business", "inflation", "rates", "gdp"},
        "market": {"stocks", "shares", "business"},
        "politics": {"government", "election", "congress", "policy"},
        "world": {"international", "global", "foreign"},
        "war": {"conflict", "military", "defense"},
        "health": {"medical", "disease", "hospital"},
        "tech": {"technology", "software", "hardware", "startup"},
        "telecom": {"carrier", "wireless", "broadband", "5g", "6g"},
    }

    expanded = set(words)
    for word in list(words):
        expanded.update(aliases.get(word, set()))
    return expanded


def overlap_score(a: set[str], b: Iterable[str]) -> int:
    b_set = set(b)
    return len(a.intersection(b_set))


def char_ngrams(text: str, n: int = 3) -> set[str]:
    normalized = re.sub(r"\s+", " ", text.lower()).strip()
    if len(normalized) < n:
        return {normalized} if normalized else set()
    return {normalized[i : i + n] for i in range(len(normalized) - n + 1)}


def ngram_similarity(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    overlap = len(a.intersection(b))
    if overlap == 0:
        return 0.0
    return overlap / math.sqrt(len(a) * len(b))
