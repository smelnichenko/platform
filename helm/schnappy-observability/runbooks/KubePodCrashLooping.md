# KubePodCrashLooping

**Severity:** warning · **For:** 15m

## What fired

Container `$labels.container` in pod `$labels.namespace/$labels.pod` restarted more than 5 times in the last hour — almost always `CrashLoopBackOff`. This KSM build doesn't expose `kube_pod_container_status_waiting_reason`, so the alert is derived from the restart-count rate, not the textbook reason metric.

## Impact

Depends entirely on the workload. A core service (admin, gateway, monitor, centrifugo, a CNPG/Strimzi pod) crash-looping is effectively an outage despite the `warning` severity. After a node reboot, old pods stuck `Failed`/`Succeeded` and shadowed by a healthy replacement are cosmetic — check the pod is actually current before treating it as an incident.

## First steps

```bash
NS=$labels.namespace; POD=$labels.pod; C=$labels.container
# Last State / Reason / Exit Code + the Events tail
kubectl -n $NS describe pod $POD | sed -n '/Last State/,/Events/p'
# Logs from the instance that crashed (note --previous)
kubectl -n $NS logs $POD -c $C --previous --tail=120
kubectl -n $NS get pod $POD -o jsonpath='restarts={.status.containerStatuses[*].restartCount} reason={.status.containerStatuses[*].lastState.terminated.reason}{"\n"}'
```

## Common causes

| Symptom | Cause |
|---|---|
| `Last State` reason `OOMKilled` | memory limit too low — raise `resources.limits.memory` in the chart; Spring Boot apps are the usual suspect |
| Killed ~`initialDelaySeconds` after start, no app error | liveness probe failing — actuator `/health` not ready in time; loosen `initialDelay`/`failureThreshold` |
| Startup log: missing env / empty config value | `ExternalSecret` not synced — check `kubectl -n $NS get externalsecret` |
| `Connection refused` to Postgres/Kafka/Keycloak at boot | dependency down (CNPG, Strimzi, Keycloak) — app exits on startup; fix the dependency first |
| App logs fine but `istio-proxy` not ready / 503s on mTLS calls | sidecar not up — check `istio-proxy` container, STRICT mTLS PeerAuth |

## Fix

Never `kubectl edit` for a permanent fix — change the chart in git and let Argo CD sync (`task deploy:*` / CD pipeline). Restart only to clear a transient flap: `kubectl -n $NS rollout restart deploy/$DEPLOY` (the Deployment owning the pod).

## Verify resolved

Restart count stops climbing (`kubectl -n $NS get pod $POD -w`) and the pod is steady `Running`/`Ready`. Alert clears once 15m pass with no new restarts.
