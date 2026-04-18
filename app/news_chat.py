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
    today = __import__("datetime").date.today().strftime("%B %d, %Y")
    system_prompt = (
        "You are the news assistant for Big Dave's News, a fact-focused news app. "
        f"Today's date is {today}. "
        "\n\n"
        "YOUR CORE PURPOSE: Help the reader understand what is actually happening — "
        "not what to think about it. Present facts so people can form their own opinions.\n\n"
        "STRICT RULES:\n"
        "- Report only what is stated or strongly implied in the provided headlines and claims. "
        "Do not add outside knowledge, speculation, or context not in the sources.\n"
        "- Never express an opinion, take a side, or editorialize. Avoid loaded language, "
        "framing, or word choices that favor one political position, party, or ideology.\n"
        "- When a topic has multiple sides or competing narratives, present all of them "
        "neutrally and proportionally. Do not emphasize one over another.\n"
        "- Distinguish clearly between confirmed facts and claims. If something is alleged, "
        "disputed, or comes from a single source, say so.\n"
        "- If the provided context does not contain enough information to answer, say so "
        "plainly. Do not fill gaps with assumptions.\n"
        "- Never tell the reader what to believe, how to feel, or what the right conclusion is.\n"
        "- Decline politely if asked anything unrelated to the news context provided.\n\n"
        "TONE: Direct, neutral, and clear. Short sentences. No jargon. "
        "Sources in the context are labeled [Headline|Source] or [Claim|Category] — "
        "you may reference the source name when relevant but do not reproduce URLs."
    )
    user_prompt = (
        f"Here are today's relevant headlines and fact-checked claims:\n\n{context}\n\n"
        f"Question: {question}\n\n"
        "Respond with 3–6 factual bullet points. Each bullet should state what is known, "
        "note where there is disagreement or uncertainty, and avoid any opinion or framing. "
        "If the topic has multiple perspectives represented in the headlines, give each one a bullet."
    )

    # Preferred path: Anthropic Claude (set ANTHROPIC_API_KEY on Render).
    anthropic_api_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
    if anthropic_api_key:
        return _ask_anthropic_llm(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            api_key=anthropic_api_key,
        )

    # Second choice: OpenAI-compatible hosted endpoint (e.g. OpenRouter).
    hosted_api_key = _resolve_hosted_api_key()
    if hosted_api_key:
        return _ask_hosted_llm(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            hosted_api_key=hosted_api_key,
        )

    # Local fallback: Ollama or another local chat-compatible endpoint.
    return _ask_local_llm(system_prompt=system_prompt, user_prompt=user_prompt)


def _ask_anthropic_llm(system_prompt: str, user_prompt: str, api_key: str) -> str:
    import anthropic  # lazy import — only needed when key is present

    model = os.getenv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
    timeout_s = float(os.getenv("ANTHROPIC_TIMEOUT_SECONDS", "30"))
    max_tokens = int(os.getenv("ANTHROPIC_MAX_TOKENS", "512"))

    client = anthropic.Anthropic(api_key=api_key)
    message = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system_prompt,
        messages=[{"role": "user", "content": user_prompt}],
        timeout=timeout_s,
    )
    content = (message.content[0].text if message.content else "").strip()
    if content:
        return content
    raise RuntimeError("Anthropic returned an empty response.")


def _ask_hosted_llm(system_prompt: str, user_prompt: str, hosted_api_key: str) -> str:
    base_url = os.getenv("HOSTED_LLM_BASE_URL", "https://openrouter.ai/api/v1").rstrip("/")
    model = os.getenv("HOSTED_LLM_MODEL", "openai/gpt-4o-mini")
    timeout_s = float(os.getenv("HOSTED_LLM_TIMEOUT_SECONDS", "30"))
    referer = os.getenv("HOSTED_LLM_REFERER", "").strip()
    app_name = os.getenv("HOSTED_LLM_APP_NAME", "Big Daves News").strip()

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
    }
    headers = {
        "Authorization": f"Bearer {hosted_api_key}",
        "Content-Type": "application/json",
    }
    if referer:
        headers["HTTP-Referer"] = referer
    if app_name:
        headers["X-Title"] = app_name

    with httpx.Client(timeout=timeout_s) as client:
        response = client.post(f"{base_url}/chat/completions", json=payload, headers=headers)
        response.raise_for_status()
        body = response.json()
        choices = body.get("choices") or []
        if not choices:
            raise RuntimeError("Hosted LLM returned no choices.")
        raw_content = (choices[0].get("message") or {}).get("content")
        if isinstance(raw_content, list):
            content = "".join(
                item.get("text", "") for item in raw_content if isinstance(item, dict)
            ).strip()
        else:
            content = (raw_content or "").strip()
        if content:
            return content
    raise RuntimeError("Hosted LLM returned an empty response.")


def _ask_local_llm(system_prompt: str, user_prompt: str) -> str:
    base_url = os.getenv("FREE_LLM_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
    model = os.getenv("FREE_LLM_MODEL", "llama3.2:3b")
    timeout_s = float(os.getenv("FREE_LLM_TIMEOUT_SECONDS", "25"))

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
    return "I could not reach the configured LLM service, but here are the closest relevant headlines:\n\n" + "\n".join(top_lines)


def _resolve_hosted_api_key() -> str:
    # Support common names so deployment config is more forgiving.
    for env_name in ("HOSTED_LLM_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY"):
        value = os.getenv(env_name, "").strip()
        if value:
            return value
    return ""


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
