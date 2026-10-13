# NodeExporterDown

**Severity:** warning · **For:** 10m

## What fired

`up{job="node-exporter"} == 0`, or no such series at all - Prometheus does not scrape the host's node_exporter
on ten.

## Impact

The Node* disk alerts are silent until this resolves.

## First steps

```bash
ssh ten 'systemctl status node_exporter --no-pager | head -20'
ssh ten 'curl -s http://192.168.11.2:9100/metrics | grep -c node_filesystem_avail_bytes'
ssh ten 'ss -lntp | grep 9100'
```

## Common causes

| Symptom | Cause |
|---|---|
| unit missing or failed | re-run `task deploy:host-hardening` |
| listening, but the scrape fails | the Prometheus pod's egress to the host (CiliumNetworkPolicy `...-prometheus-egress-node-exporter`) |
| no `up` series | the ScrapeConfig gone - `nodeExporter.enabled` in schnappy-observability's values |
