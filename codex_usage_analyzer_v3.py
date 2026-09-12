#!/usr/bin/env python3
"""
Codex Usage Analyzer v3
Liest lokale Codex-Rollout-Logs und erzeugt:
  - codex_usage_sessions.csv
  - codex_usage_projects.csv
  - codex_usage_daily.csv
  - codex_usage_report.html

Keine externen Python-Pakete erforderlich.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

# Standard-Credits pro 1 Mio Tokens, geprüft am 12.09.2026.
# Quelle: https://learn.chatgpt.com/docs/pricing#token-rates
RATE_CARD_DATE = "12.09.2026"
RATES = {
    "gpt-6-astra":   (250.0, 25.0, 1250.0),
    "gpt-5.6-sol":   (100.0, 10.0, 500.0),
    "gpt-5.6-terra": (50.0, 5.0, 300.0),
    "gpt-5.6-luna":  (5.0, 0.5, 30.0),
    "gpt-5.5":       (125.0, 12.5, 750.0),
    "gpt-5.4":       (62.5, 6.25, 375.0),
    "gpt-5.4-mini":  (18.75, 1.875, 113.0),
    # Beibehaltene Altraten vom 23.07.2026, in der aktuellen Karte nicht mehr gelistet.
    "gpt-5.3-codex": (43.75, 4.375, 350.0),
    "gpt-5.2":       (43.75, 4.375, 350.0),
}

def nested_get(obj: Any, paths: Iterable[tuple[str, ...]], default=None):
    for path in paths:
        cur = obj
        ok = True
        for key in path:
            if not isinstance(cur, dict) or key not in cur:
                ok = False
                break
            cur = cur[key]
        if ok and cur is not None:
            return cur
    return default

def parse_timestamp(value: Any, fallback_mtime: float) -> datetime:
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.fromtimestamp(fallback_mtime, tz=timezone.utc)

def normalize_model(model: str) -> str:
    s = (model or "unbekannt").lower().strip()
    s = s.replace("_", "-").replace(" ", "-")
    aliases = {
        "astra": "gpt-6-astra",
        "6-astra": "gpt-6-astra",
        "gpt-5.6": "gpt-5.6-sol",
        "sol": "gpt-5.6-sol",
        "terra": "gpt-5.6-terra",
        "luna": "gpt-5.6-luna",
        "5.6-sol": "gpt-5.6-sol",
        "5.6-terra": "gpt-5.6-terra",
        "5.6-luna": "gpt-5.6-luna",
    }
    return aliases.get(s, s)

def normalize_effort(effort: str) -> str:
    """Normalisiert die in Codex-Logs vorkommenden Aufwandstufen."""
    raw = (effort or "").strip().lower().replace("_", "-")
    aliases = {
        "none": "kein",
        "minimal": "minimal",
        "low": "niedrig",
        "medium": "mittel",
        "high": "hoch",
        "xhigh": "sehr hoch",
        "extra-high": "sehr hoch",
        "very-high": "sehr hoch",
        "max": "sehr hoch",
    }
    return aliases.get(raw, raw or "unbekannt")

def project_name(cwd: str) -> str:
    if not cwd:
        return "(kein Arbeitsordner)"
    p = Path(cwd).expanduser()
    return p.name or str(p)

def truncate(text: str, n: int = 110) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= n else text[: n - 1] + "…"

def extract_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        pieces = []
        for item in value:
            if isinstance(item, str):
                pieces.append(item)
            elif isinstance(item, dict):
                t = item.get("text") or item.get("content") or item.get("input_text")
                if isinstance(t, str):
                    pieces.append(t)
        return " ".join(pieces)
    if isinstance(value, dict):
        for k in ("text", "content", "input_text", "message"):
            if k in value:
                return extract_text(value[k])
    return ""

def is_probable_user_message(obj: dict[str, Any]) -> bool:
    payload = obj.get("payload", obj)
    role = nested_get(payload, [
        ("role",), ("message", "role"), ("item", "role")
    ], "")
    typ = str(nested_get(payload, [
        ("type",), ("message", "type"), ("item", "type")
    ], "")).lower()
    return str(role).lower() == "user" or typ in {"user_message", "user_input"}

def usage_from_obj(obj: dict[str, Any]) -> dict[str, int] | None:
    payload = obj.get("payload", obj)
    typ = str(payload.get("type", "")).lower()
    if typ not in {"token_count", "turn.completed", "turn_completed"} and "usage" not in payload:
        # Manche Versionen verschachteln das Event tiefer.
        if not isinstance(payload.get("info"), dict):
            return None

    usage = nested_get(payload, [
        ("info", "total_token_usage"),
        ("total_token_usage",),
        ("usage",),
        ("info", "usage"),
    ])
    if not isinstance(usage, dict):
        return None

    def num(*keys: str) -> int:
        for k in keys:
            v = usage.get(k)
            if isinstance(v, (int, float)):
                return int(v)
        return 0

    inp = num("input_tokens", "prompt_tokens")
    cached = num("cached_input_tokens", "cached_tokens", "input_cached_tokens")
    out = num("output_tokens", "completion_tokens")
    reasoning = num("reasoning_output_tokens", "reasoning_tokens")
    total = num("total_tokens")
    if not total:
        total = inp + out
    if not any((inp, cached, out, reasoning, total)):
        return None
    return {
        "input": inp,
        "cached": cached,
        "output": out,
        "reasoning": reasoning,
        "total": total,
    }

def estimated_credits(model: str, input_tokens: int, cached: int, output: int) -> float | None:
    key = normalize_model(model)
    # Nur datierte Snapshots zuordnen; unbekannte Modellvarianten nicht erraten.
    base = re.sub(r"-[0-9]{4}-[0-9]{2}-[0-9]{2}$", "", key)
    rate = RATES.get(base)
    if rate is None:
        return None
    input_rate, cache_rate, output_rate = rate
    # Die Logs führen cached_input_tokens üblicherweise als Teilmenge von input_tokens.
    uncached = max(0, input_tokens - cached)
    return (uncached * input_rate + cached * cache_rate + output * output_rate) / 1_000_000

def analyze_file(path: Path) -> dict[str, Any] | None:
    mtime = path.stat().st_mtime
    first_dt = None
    last_dt = None
    cwd = ""
    model = ""
    effort = ""
    model_effort_history: list[str] = []
    first_prompt = ""
    session_id = ""
    latest_usage = None
    max_usage = {"input": 0, "cached": 0, "output": 0, "reasoning": 0, "total": 0}
    malformed = 0

    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    malformed += 1
                    continue
                if not isinstance(obj, dict):
                    continue

                dt = parse_timestamp(
                    nested_get(obj, [
                        ("timestamp",), ("created_at",), ("time",),
                        ("payload", "timestamp")
                    ]),
                    mtime,
                )
                first_dt = dt if first_dt is None or dt < first_dt else first_dt
                last_dt = dt if last_dt is None or dt > last_dt else last_dt

                payload = obj.get("payload", obj)
                if not cwd:
                    cwd = str(nested_get(payload, [
                        ("cwd",), ("turn_context", "cwd"), ("session", "cwd"),
                        ("metadata", "cwd"), ("context", "cwd")
                    ], "") or "")
                detected_model = str(nested_get(payload, [
                    ("model",),
                    ("turn_context", "model"),
                    ("session", "model"),
                    ("metadata", "model"),
                    ("model_name",),
                    ("config", "model"),
                    ("settings", "model"),
                    ("request", "model"),
                ], "") or "")

                detected_effort = str(nested_get(payload, [
                    ("effort",),
                    ("reasoning_effort",),
                    ("reasoning", "effort"),
                    ("turn_context", "effort"),
                    ("turn_context", "reasoning_effort"),
                    ("session", "effort"),
                    ("session", "reasoning_effort"),
                    ("metadata", "effort"),
                    ("metadata", "reasoning_effort"),
                    ("config", "effort"),
                    ("config", "reasoning_effort"),
                    ("settings", "effort"),
                    ("settings", "reasoning_effort"),
                    ("request", "reasoning_effort"),
                ], "") or "")

                # turn_context kann sich innerhalb einer Session ändern. Für die
                # Session-Auswertung verwenden wir den zuletzt erkannten Stand.
                if detected_model:
                    model = detected_model
                if detected_effort:
                    effort = detected_effort

                if detected_model or detected_effort:
                    combo = (
                        f"{normalize_model(detected_model or model)} / "
                        f"{normalize_effort(detected_effort or effort)}"
                    )
                    if combo not in model_effort_history:
                        model_effort_history.append(combo)

                if not session_id:
                    session_id = str(nested_get(payload, [
                        ("session_id",), ("thread_id",), ("id",),
                        ("metadata", "session_id")
                    ], "") or "")

                if not first_prompt and is_probable_user_message(obj):
                    text = extract_text(nested_get(payload, [
                        ("content",), ("message", "content"), ("item", "content"),
                        ("text",), ("message",)
                    ], ""))
                    if text:
                        first_prompt = truncate(text)

                usage = usage_from_obj(obj)
                if usage:
                    latest_usage = usage
                    for key in max_usage:
                        max_usage[key] = max(max_usage[key], usage[key])
    except OSError as exc:
        print(f"WARNUNG: {path}: {exc}", file=sys.stderr)
        return None

    if latest_usage is None:
        return None

    # Cumulative Zähler können bei einzelnen Versionen kurz zurückspringen.
    # Der höchste beobachtete Gesamtstand ist dafür sicherer als das Addieren aller Events.
    usage = max_usage
    dt = last_dt or datetime.fromtimestamp(mtime, tz=timezone.utc)
    model = normalize_model(model)
    effort = normalize_effort(effort)
    credits = estimated_credits(model, usage["input"], usage["cached"], usage["output"])

    return {
        "date": dt.astimezone().strftime("%Y-%m-%d"),
        "started": (first_dt or dt).astimezone().isoformat(timespec="seconds"),
        "ended": dt.astimezone().isoformat(timespec="seconds"),
        "project": project_name(cwd),
        "cwd": cwd,
        "task": first_prompt or "(Aufgabentext nicht erkannt)",
        "model": model,
        "effort": effort,
        "model_effort_history": " → ".join(model_effort_history) if model_effort_history else f"{model} / {effort}",
        "input_tokens": usage["input"],
        "cached_input_tokens": usage["cached"],
        "uncached_input_tokens": max(0, usage["input"] - usage["cached"]),
        "output_tokens": usage["output"],
        "reasoning_tokens": usage["reasoning"],
        "total_tokens": usage["total"],
        "estimated_credits": credits,
        "session_id": session_id or path.stem,
        "log_file": str(path),
        "malformed_lines": malformed,
    }

def aggregate(rows: list[dict[str, Any]], key_fields: tuple[str, ...]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], dict[str, Any]] = {}
    numeric = (
        "input_tokens", "cached_input_tokens", "uncached_input_tokens",
        "output_tokens", "reasoning_tokens", "total_tokens"
    )
    for row in rows:
        key = tuple(row[k] for k in key_fields)
        if key not in groups:
            groups[key] = {k: row[k] for k in key_fields}
            groups[key]["sessions"] = 0
            groups[key]["estimated_credits"] = 0.0
            groups[key]["credits_complete"] = True
            groups[key]["_models"] = set()
            groups[key]["_efforts"] = set()
            for n in numeric:
                groups[key][n] = 0
        g = groups[key]
        g["sessions"] += 1
        for n in numeric:
            g[n] += int(row[n])
        if row.get("model"):
            g["_models"].add(row["model"])
        if row.get("effort"):
            g["_efforts"].add(row["effort"])
        if row["estimated_credits"] is None:
            g["credits_complete"] = False
        else:
            g["estimated_credits"] += float(row["estimated_credits"])

    result = []
    for g in groups.values():
        g["models"] = ", ".join(sorted(g.pop("_models")))
        g["efforts"] = ", ".join(sorted(g.pop("_efforts")))
        result.append(g)
    return sorted(result, key=lambda x: x["total_tokens"], reverse=True)

def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str] | None = None):
    if not rows:
        return
    fields = fields or list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

def fmt(n: Any) -> str:
    if n is None:
        return "–"
    if isinstance(n, float):
        return f"{n:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"{int(n):,}".replace(",", ".")

def make_table(rows: list[dict[str, Any]], columns: list[tuple[str, str]], limit: int | None = None) -> str:
    shown = rows[:limit] if limit else rows
    head = "".join(f"<th>{html.escape(label)}</th>" for _, label in columns)
    body = []
    for row in shown:
        cells = []
        for key, _ in columns:
            value = row.get(key)
            if key == "estimated_credits":
                display = "–" if value is None else fmt(value)
            elif isinstance(value, (int, float)):
                display = fmt(value)
            else:
                display = html.escape(str(value))
            title = html.escape(str(value))
            cells.append(f'<td title="{title}">{display}</td>')
        body.append("<tr>" + "".join(cells) + "</tr>")
    return f"<table><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table>"

def compact_num(n: int | float | None) -> str:
    if n is None:
        return "–"
    value = float(n)
    for divisor, suffix in ((1_000_000_000, " Mrd."), (1_000_000, " Mio."), (1_000, " Tsd.")):
        if abs(value) >= divisor:
            number = value / divisor
            decimals = 0 if number >= 100 else 1
            return f"{number:.{decimals}f}".replace(".", ",") + suffix
    return fmt(int(value))


def session_duration(started: str, ended: str) -> str:
    try:
        start = datetime.fromisoformat(started)
        end = datetime.fromisoformat(ended)
        seconds = max(0, int((end - start).total_seconds()))
    except (TypeError, ValueError):
        return "–"
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours} h {minutes:02d} min"
    if minutes:
        return f"{minutes} min {secs:02d} s"
    return f"{secs} s"


def write_html(
    path: Path,
    sessions: list[dict[str, Any]],
    projects: list[dict[str, Any]],
    daily: list[dict[str, Any]],
    model_effort: list[dict[str, Any]],
):
    total_tokens = sum(r["total_tokens"] for r in sessions)
    input_tokens = sum(r["input_tokens"] for r in sessions)
    cached = sum(r["cached_input_tokens"] for r in sessions)
    uncached = sum(r["uncached_input_tokens"] for r in sessions)
    output = sum(r["output_tokens"] for r in sessions)
    known_credits = sum(r["estimated_credits"] or 0 for r in sessions)
    unknown_models = sorted({r["model"] for r in sessions if r["estimated_credits"] is None})
    cache_ratio = (cached / input_tokens * 100) if input_tokens else 0

    daily_sorted = sorted(daily, key=lambda r: r["date"])
    max_daily = max((r["estimated_credits"] for r in daily_sorted), default=0) or 1

    warning = ""
    if unknown_models:
        warning = (
            "<div class='notice'><span>!</span><div><strong>Kosten teilweise unbekannt</strong>"
            "<p>Keine Rate hinterlegt für: " + html.escape(", ".join(unknown_models)) +
            ". Tokens werden dennoch vollständig angezeigt.</p></div></div>"
        )

    model_cards = []
    for row in model_effort:
        credits = "–" if not row.get("credits_complete", True) else f"{row['estimated_credits']:,.2f} Credits"
        model_cards.append(f'''
        <article class="model-card">
          <div class="model-head"><span class="model-dot"></span><strong>{html.escape(row['model'])}</strong></div>
          <div class="model-effort">Aufwand: {html.escape(row['effort'])}</div>
          <dl>
            <div><dt>Sessions</dt><dd>{fmt(row['sessions'])}</dd></div>
            <div><dt>Input</dt><dd>{compact_num(row['input_tokens'])}</dd></div>
            <div><dt>Cache</dt><dd>{compact_num(row['cached_input_tokens'])}</dd></div>
            <div><dt>Output</dt><dd>{compact_num(row['output_tokens'])}</dd></div>
          </dl>
          <div class="model-cost">{credits}</div>
        </article>''')

    bars = []
    for row in daily_sorted:
        value = float(row.get("estimated_credits") or 0)
        height = max(2, value / max_daily * 100) if value else 2
        label = datetime.fromisoformat(row["date"]).strftime("%d.%m.")
        title = f"{row['date']}: {value:,.2f} Credits; {fmt(row['total_tokens'])} Tokens"
        bars.append(f'''
          <div class="bar-item" title="{html.escape(title)}">
            <div class="bar-value">{value:,.0f}</div>
            <div class="bar-track"><div class="bar" style="height:{height:.2f}%"></div></div>
            <div class="bar-label">{label}</div>
          </div>''')

    project_rows = []
    for row in projects:
        credits = "–" if not row.get("credits_complete", True) else f"{row['estimated_credits']:,.2f} Credits"
        cache_pct = row['cached_input_tokens'] / row['input_tokens'] * 100 if row['input_tokens'] else 0
        project_rows.append(f'''
          <tr>
            <td><strong>{html.escape(row['project'])}</strong><small>{html.escape(row['cwd'])}</small></td>
            <td>{html.escape(row.get('models',''))}</td><td>{html.escape(row.get('efforts',''))}</td>
            <td>{fmt(row['sessions'])}</td><td>{compact_num(row['input_tokens'])}</td>
            <td>{compact_num(row['cached_input_tokens'])}<small>{cache_pct:.1f} %</small></td>
            <td>{compact_num(row['output_tokens'])}</td><td>{compact_num(row['total_tokens'])}</td>
            <td class="money">{credits}</td>
          </tr>''')

    session_cards = []
    for row in sorted(sessions, key=lambda r: r["ended"], reverse=True):
        cost = "nicht berechenbar" if row["estimated_credits"] is None else f"{row['estimated_credits']:,.2f} Credits"
        dt = datetime.fromisoformat(row["ended"])
        cache_pct = row['cached_input_tokens'] / row['input_tokens'] * 100 if row['input_tokens'] else 0
        search_blob = " ".join(str(row.get(k, "")) for k in ("project", "task", "model", "effort")).lower()
        session_cards.append(f'''
        <article class="session" data-project="{html.escape(row['project'].lower())}" data-model="{html.escape(row['model'].lower())}" data-effort="{html.escape(row['effort'].lower())}" data-search="{html.escape(search_blob)}">
          <div class="session-main">
            <div class="session-title-row"><span class="badge">CODEX</span><strong>{html.escape(row['project'])}</strong><span class="task">{html.escape(row['task'])}</span></div>
            <div class="session-meta"><span>{html.escape(row['model'])}</span><span>{html.escape(row['effort'])}</span><span>{dt.strftime('%d.%m.%Y, %H:%M')}</span><span>{session_duration(row['started'], row['ended'])}</span></div>
            <div class="token-line"><span><b>frisch</b> {compact_num(row['uncached_input_tokens'])}</span><span><b>cached</b> {compact_num(row['cached_input_tokens'])} ({cache_pct:.1f} %)</span><span><b>output</b> {compact_num(row['output_tokens'])}</span><span><b>reasoning</b> {compact_num(row['reasoning_tokens'])}</span></div>
          </div>
          <div class="session-cost"><strong>{cost}</strong><small>geschätzte Codex-Credits</small></div>
        </article>''')

    model_options = ''.join(f'<option value="{html.escape(x.lower())}">{html.escape(x)}</option>' for x in sorted({r['model'] for r in sessions}))
    effort_options = ''.join(f'<option value="{html.escape(x.lower())}">{html.escape(x)}</option>' for x in sorted({r['effort'] for r in sessions}))

    doc = f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Codex-Verbrauch</title>
<style>
:root{{--bg:#f4f3ef;--panel:#fbfaf7;--text:#232522;--muted:#777970;--line:#d9d7cf;--green:#2e7854;--orange:#c87539;--shadow:0 1px 2px #0000000b}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--text);font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px}}main{{max-width:1440px;margin:auto;padding:34px 28px 60px}}h1,h2,p{{margin:0}}h1{{font-size:18px;letter-spacing:.08em;text-transform:uppercase}}
.header{{display:flex;justify-content:space-between;align-items:flex-end;padding-bottom:18px;border-bottom:1px solid var(--line)}}.header-title{{display:flex;align-items:center;gap:10px}}.header-title:before{{content:"";width:8px;height:8px;border-radius:50%;background:var(--green)}}.total{{text-align:right;color:var(--muted);font-size:11px;letter-spacing:.12em;text-transform:uppercase}}.total strong{{display:block;color:var(--text);font-size:25px;letter-spacing:0}}.sub{{color:var(--muted);font-size:12px;margin-top:6px}}
.notice{{display:flex;gap:12px;border:1px solid #cdbb76;background:#fffdf4;padding:11px 14px;margin:18px 0}}.notice p{{color:var(--muted);margin-top:2px;font-size:12px}}.section-title{{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#696b64;margin:28px 0 12px;display:flex;align-items:center;gap:12px}}.section-title:after{{content:"";height:1px;background:var(--line);flex:1}}
.summary-grid{{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:10px}}.summary-card,.model-card{{background:var(--panel);border:1px solid #e5e2da;box-shadow:var(--shadow);padding:16px}}.summary-card small{{display:block;color:var(--muted);text-transform:uppercase;letter-spacing:.1em;font-size:10px}}.summary-card strong{{display:block;font-size:22px;margin-top:7px}}
.model-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px}}.model-head{{display:flex;align-items:center;gap:8px;text-transform:uppercase;font-size:11px;letter-spacing:.08em}}.model-dot{{width:8px;height:8px;background:var(--green);border-radius:50%}}.model-effort{{color:var(--muted);font-size:12px;margin:7px 0 14px}}dl{{margin:0}}dl div{{display:flex;justify-content:space-between;padding:3px 0}}dt{{color:var(--muted)}}dd{{margin:0;font-variant-numeric:tabular-nums}}.model-cost{{font-size:19px;font-weight:700;text-align:right;margin-top:12px}}
.chart-panel,.table-panel,.sessions-panel{{background:var(--panel);border:1px solid #e5e2da;padding:16px;box-shadow:var(--shadow)}}.chart{{height:250px;display:flex;gap:7px;align-items:stretch;border-bottom:1px solid var(--line);padding:12px 4px 0}}.bar-item{{flex:1;min-width:22px;display:grid;grid-template-rows:20px 1fr 24px;text-align:center}}.bar-value{{font-size:9px;color:var(--muted)}}.bar-track{{position:relative;height:100%;display:flex;align-items:flex-end}}.bar{{width:70%;margin:auto;background:linear-gradient(180deg,var(--orange),#d89562);min-height:2px}}.bar-label{{font-size:10px;color:var(--muted);padding-top:6px}}
.table-wrap{{overflow:auto}}table{{width:100%;border-collapse:collapse;white-space:nowrap}}th{{font-size:10px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);text-align:right;padding:10px;border-bottom:1px solid var(--line)}}th:first-child,td:first-child{{text-align:left}}td{{padding:12px 10px;text-align:right;border-bottom:1px solid #e8e6df;font-variant-numeric:tabular-nums}}td small{{display:block;color:var(--muted);font-size:10px;margin-top:3px;max-width:360px;overflow:hidden;text-overflow:ellipsis}}.money{{font-weight:700}}
.filters{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}}input,select{{background:#fff;border:1px solid var(--line);padding:8px 10px;color:var(--text);font:inherit}}input{{min-width:280px;flex:1}}.session{{display:grid;grid-template-columns:1fr 180px;gap:18px;padding:14px 12px;border-top:1px solid #e1dfd8;background:var(--panel)}}.session:first-of-type{{border-top:0}}.session-title-row{{display:flex;align-items:baseline;gap:9px;min-width:0}}.badge{{font-size:9px;letter-spacing:.08em;border:1px solid #9da29c;padding:2px 5px;color:#626762}}.task{{color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}.session-meta,.token-line{{display:flex;gap:11px;flex-wrap:wrap;color:var(--muted);font-size:11px;margin-top:6px}}.token-line b{{color:#5d605a;font-weight:600}}.session-cost{{text-align:right;align-self:center}}.session-cost strong{{font-size:18px;display:block}}.session-cost small{{color:var(--muted);font-size:10px}}.empty{{display:none;text-align:center;color:var(--muted);padding:30px}}footer{{color:var(--muted);font-size:11px;line-height:1.5;margin-top:22px}}
@media(max-width:900px){{.summary-grid{{grid-template-columns:repeat(2,1fr)}}.session{{grid-template-columns:1fr}}.session-cost{{text-align:left}}}}@media(max-width:560px){{main{{padding:20px 12px}}.summary-grid{{grid-template-columns:1fr 1fr}}.header{{align-items:flex-start}}.total strong{{font-size:19px}}input{{min-width:100%}}}}@media(prefers-color-scheme:dark){{:root{{--bg:#191a18;--panel:#232420;--text:#ecece7;--muted:#a6a79f;--line:#3d3e38;--shadow:none}}input,select{{background:#1d1e1b;color:var(--text)}}.summary-card,.model-card,.chart-panel,.table-panel,.sessions-panel,.session{{border-color:#353630}}td{{border-color:#353630}}}}
</style></head><body><main>
<header class="header"><div><div class="header-title"><h1>Codex-Verbrauch</h1></div><p class="sub">Lokale Sitzungslogs · erzeugt am {html.escape(datetime.now().astimezone().strftime('%d.%m.%Y, %H:%M'))}</p></div><div class="total">geschätzte Credits (bekannte Raten)<strong>{known_credits:,.2f} Credits</strong></div></header>{warning}
<h2 class="section-title">Übersicht</h2><div class="summary-grid"><div class="summary-card"><small>Sessions</small><strong>{fmt(len(sessions))}</strong></div><div class="summary-card"><small>Token gesamt</small><strong>{compact_num(total_tokens)}</strong></div><div class="summary-card"><small>Frischer Input</small><strong>{compact_num(uncached)}</strong></div><div class="summary-card"><small>Cached Input</small><strong>{compact_num(cached)}</strong></div><div class="summary-card"><small>Cache-Anteil</small><strong>{cache_ratio:.1f} %</strong></div><div class="summary-card"><small>Output</small><strong>{compact_num(output)}</strong></div></div>
<h2 class="section-title">Summen nach Modell und Aufwand</h2><div class="model-grid">{''.join(model_cards)}</div>
<h2 class="section-title">Verlauf: Credits pro Tag</h2><section class="chart-panel"><div class="chart">{''.join(bars)}</div></section>
<h2 class="section-title">Projekte</h2><section class="table-panel"><div class="table-wrap"><table><thead><tr><th>Projekt</th><th>Modell</th><th>Aufwand</th><th>Sessions</th><th>Input</th><th>Cache</th><th>Output</th><th>Gesamt</th><th>Credits*</th></tr></thead><tbody>{''.join(project_rows)}</tbody></table></div></section>
<h2 class="section-title">Sessions</h2><section class="sessions-panel"><div class="filters"><input id="search" type="search" placeholder="Projekt oder Aufgabe durchsuchen …"><select id="model"><option value="">Alle Modelle</option>{model_options}</select><select id="effort"><option value="">Alle Aufwände</option>{effort_options}</select></div><div id="sessions">{''.join(session_cards)}</div><div id="empty" class="empty">Keine passenden Sessions gefunden.</div></section>
<footer>* Geschätzte Codex-Credits zu Standardraten, Preisstand {RATE_CARD_DATE} (OpenAI Codex Rate Card). Alle Sessions werden mit diesen Raten neu bewertet; keine historische Abrechnung. GPT-5.3-Codex und GPT-5.2 verwenden die hinterlegten Altraten vom 23.07.2026. Fast-Modus, Langkontext- und Cache-Schreibaufschläge werden nicht berücksichtigt. Credits sind keine US-Dollar und entsprechen nicht zwingend dem tatsächlichen Kontingentverbrauch. Cached Input wird als Teilmenge des Input-Werts behandelt. Pro Session wird der höchste kumulierte Tokenstand verwendet.</footer>
<script>const search=document.getElementById('search'),model=document.getElementById('model'),effort=document.getElementById('effort');function filterSessions(){{const q=search.value.trim().toLowerCase(),m=model.value,e=effort.value;let visible=0;document.querySelectorAll('.session').forEach(el=>{{const ok=(!q||el.dataset.search.includes(q))&&(!m||el.dataset.model===m)&&(!e||el.dataset.effort===e);el.style.display=ok?'grid':'none';if(ok)visible++;}});document.getElementById('empty').style.display=visible?'none':'block';}}[search,model,effort].forEach(el=>el.addEventListener('input',filterSessions));</script></main></body></html>'''
    path.write_text(doc, encoding="utf-8")

def main():
    parser = argparse.ArgumentParser(description="Lokale Codex-Token nach Projekt und Aufgabe auswerten")
    parser.add_argument("--sessions-dir", type=Path, default=Path.home() / ".codex" / "sessions")
    parser.add_argument("--output-dir", type=Path, default=Path.cwd() / "codex-usage-report")
    parser.add_argument("--since", help="Nur Sessions ab Datum YYYY-MM-DD")
    args = parser.parse_args()

    root = args.sessions_dir.expanduser()
    out = args.output_dir.expanduser()
    if not root.exists():
        print(f"Codex-Sitzungsordner nicht gefunden: {root}", file=sys.stderr)
        print("Prüfe ggf.: find ~/.codex -name 'rollout-*.jsonl' | head", file=sys.stderr)
        sys.exit(2)

    files = sorted(root.rglob("rollout-*.jsonl"))
    if not files:
        print(f"Keine rollout-*.jsonl unter {root} gefunden.", file=sys.stderr)
        sys.exit(3)

    rows = []
    for i, path in enumerate(files, 1):
        row = analyze_file(path)
        if row and (not args.since or row["date"] >= args.since):
            rows.append(row)
        if i % 100 == 0:
            print(f"{i}/{len(files)} Logs gelesen …", file=sys.stderr)

    if not rows:
        print("Keine auswertbaren Token-Daten gefunden.", file=sys.stderr)
        sys.exit(4)

    out.mkdir(parents=True, exist_ok=True)
    projects = aggregate(rows, ("project", "cwd"))
    daily = aggregate(rows, ("date",))
    model_effort = aggregate(rows, ("model", "effort"))

    write_csv(out / "codex_usage_sessions.csv", rows)
    write_csv(out / "codex_usage_projects.csv", projects)
    write_csv(out / "codex_usage_daily.csv", daily)
    write_csv(out / "codex_usage_models_effort.csv", model_effort)
    write_html(out / "codex_usage_report.html", rows, projects, daily, model_effort)

    print(f"\nAusgewertet: {len(rows)} Sessions aus {len(files)} Logdateien")
    print(f"Bericht:     {out / 'codex_usage_report.html'}")
    print(f"Projekt-CSV: {out / 'codex_usage_projects.csv'}")
    print(f"Session-CSV: {out / 'codex_usage_sessions.csv'}")
    print(f"Modell-CSV:  {out / 'codex_usage_models_effort.csv'}")
    print("\nAuf macOS öffnen:")
    print(f"open {json.dumps(str(out / 'codex_usage_report.html'))}")

if __name__ == "__main__":
    main()
