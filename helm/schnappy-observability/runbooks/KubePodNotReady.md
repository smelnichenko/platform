# KubePodNotReady

**Severity:** warning · **For:** 15m

## What fired

Pod `$labels.namespace/$labels.pod` has been stuck in `$labels.phase` (Pending or Unknown) for 15+ min. **Pending** = not scheduled or containers not started (ImagePullBackOff and unschedulable both sit here). **Unknown** = the kubelet stopped reporting the pod. The rule is scoped to Pending|Unknown on purpose — Failed/Succeeded floods after a node reboot from terminal pods shadowed by a healthy replica.

## Impact

That replica is doing no work. If it's the only one for a service, that service is degraded or down. Unknown on this single node means the node itself stopped reporting — likely a cluster-wide problem.

## First steps

```bash
NS=$labels.namespace; POD=$labels.pod
# Events at the BOTTOM are the signal
kubectl -n $NS describe pod $POD | sed -n '/Events:/,$p'
kubectl -n $NS get pod $POD -o jsonpath='phase={.status.phase} reason={.status.reason}{"\n"}'
# Unknown? the node is the only suspect — investigate ten directly
kubectl get nodes
```

## Common causes

| Phase / Events | Cause |
|---|---|
| `Pending` + `FailedScheduling` Insufficient cpu/memory | resource pressure — only node `ten`, nothing to reschedule to; free capacity or lower requests |
| `Pending` + nodeSelector/taint / `node(s) had untolerated taint` | `ten` cordoned or tainted — `kubectl uncordon ten`, fix mismatch in chart |
| `Pending` + `FailedScheduling` unbound PVC | check `kubectl -n $NS get pvc` — pending PVC, missing storageClass |
| `ImagePullBackOff` / `ErrImagePull` | bad tag, registry creds, or Nexus proxy down (most pulls go via Nexus) |
| `Pending`, stuck on init container | init container blocking — `kubectl -n $NS logs $POD -c <init>` |
| `Pending`, no `istio-proxy` injected | sidecar injection issue — check namespace `istio-injection` label / webhook |
| `Unknown` | kubelet down / node NotReady — see `kubectl get nodes`, then SSH `ten` (`systemctl status kubelet`, `containerd`) |

## Verify resolved

`kubectl -n $NS get pod $POD` shows `Running` and `1/1` Ready (Istio sidecar counted), and the alert clears after 15m with no new Pending/Unknown pods.
