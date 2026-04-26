# Watchdog

**Severity:** none · **For:** (always)

## What fired

This is the **dead man's switch**. Watchdog fires a permanent `vector(1)` alert. It's *expected* to be firing at all times.

## When it stops being a problem

When you stop seeing it, the alerting pipeline is broken:
- Prometheus down or unreachable
- Alertmanager down
- Notification path (SMTP, webhook) broken — but Watchdog by design has `severity: none` so it isn't routed; it's checked externally

## Verify the chain (manually, periodically)

```bash
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/alerts' | python3 -c '
import json,sys
d=json.load(sys.stdin)
print([a["labels"]["alertname"] for a in d["data"]["alerts"] if a["labels"]["alertname"]=="Watchdog"])
'
```
Should return `['Watchdog']`. If empty, Prometheus isn't evaluating rules.

```bash
kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -- \
  wget -qO- 'http://localhost:9093/api/v2/alerts' | python3 -c '
import json,sys; print([a["labels"]["alertname"] for a in json.load(sys.stdin) if a["labels"]["alertname"]=="Watchdog"])
'
```
Should also include `Watchdog`. If only the first command sees it, Prometheus → Alertmanager link is broken.

## Why a runbook for an always-firing alert

So the `runbook_url` doesn't 404 in dashboards. And so future-you remembers that the *absence* of this alert is the actionable signal, not its presence.
