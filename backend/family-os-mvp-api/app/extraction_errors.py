"""Map extraction failures to short, user-safe messages (no secrets)."""


def public_message(exc: BaseException) -> str:
    """Return a message safe to show in the iOS app and API JSON."""
    s = str(exc)
    low = s.lower()

    if "openai_api_key is not set" in low or ("api key" in low and "not set" in low):
        return "Server missing OPENAI_API_KEY. Add it under Render → Environment for this service."

    if "401" in s or "invalid_api_key" in low or "incorrect api key" in low or "invalid x-api-key" in low:
        return "OpenAI rejected the API key. Regenerate the key and update OPENAI_API_KEY on Render."

    if "429" in s or "rate_limit" in low or "ratelimit" in low or "too many requests" in low:
        return "OpenAI rate limit. Wait a minute and try again."

    if "insufficient_quota" in low:
        return "OpenAI quota exceeded. Check billing and usage at platform.openai.com."

    if "model" in low and any(x in low for x in ("not found", "does not exist", "invalid model")):
        return "AI model not available. On Render set OPENAI_MODEL to gpt-4o-mini and redeploy."

    if "OpenAI extraction failed for all models" in s:
        return "OpenAI could not complete extraction. Check API key, billing, and OPENAI_MODEL (use gpt-4o-mini)."

    if "connection" in low or "timeout" in low or "timed out" in low:
        return "Could not reach OpenAI. Try again; if it persists, check Render logs and network."

    return "Could not extract events. See Render service logs for the technical error."
