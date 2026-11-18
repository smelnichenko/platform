# IstioGatewayProxyBehind

**Severity:** warning · **For:** 2h

## What fired

A running pod of the ingress gateway (`<namespace>/<...>-gateway-istio-...`) runs an `istio-proxy` image whose tag is
not istiod's (`kube_pod_container_info`, the tags compared), for 2 h. The gateway's Deployment is Istio's gateway
controller's: it renders it from the Gateway and the ConfigMap its `infrastructure.parametersRef` names
(`<fullname>-gateway-options`, schnappy-mesh's `gateway.yaml`). With that ConfigMap gone, or holding a key the controller
does not take (only deployment, service, serviceAccount, horizontalPodAutoscaler, podDisruptionBudget), the controller
stops reconciling the gateway: its pods stay at the old Istio after an upgrade, and its Service's options are no longer
kept.

## How bad

Ingress still answers on the old proxy - the gateway runs, but outside the mesh's version: a proxy older than istiod
by more than Istio's skew policy stops working with it, and the Service's externalIPs are no longer reasserted.

## First steps

```bash
kubectl -n schnappy-infra get configmap schnappy-infra-gateway-options -o yaml
kubectl -n schnappy-infra get gateway schnappy-infra-gateway -o jsonpath='{.spec.infrastructure}{"\n"}{.status.conditions}{"\n"}'
kubectl -n istio-system logs deploy/istiod --since=3h | grep -i -E 'parametersRef|gateway.*(render|overlay|configmap)'
kubectl -n schnappy-infra get pods -l gateway.networking.k8s.io/gateway-name=schnappy-infra-gateway -o wide
```

## Fix

- The ConfigMap missing: re-sync `schnappy-infra-mesh` (Argo makes it again; the controller re-renders on its event).
- A key the controller refused (`unsupported overlay`): fix `gateway.yaml` in platform - only the five keys above.
- The controller reconciles but the pods stay: a mesh restart (ops: `task deploy:mesh:restart`) rolls them.

## Verification

Every running gateway pod's `istio-proxy` image on istiod's tag; the alert resolves.
