# schnappy-auth — **TEST ONLY**

Deploys an in-cluster Keycloak (Deployment + Service + HTTPRoute-ready
Ingress + realm ConfigMap + ExternalSecrets + NetworkPolicies).

## Not used in production

Production Keycloak runs **bare-metal on the Pis** via
`setup-pi-services.yml`, reached through Caddy on VIP `192.168.11.5`
as `auth.pmon.dev`. There is **no ArgoCD Application** for this chart
and no values file in `infra/clusters/production/schnappy-auth/`.

## Where it IS used

Vagrant E2E test harness — `tests/ansible/tasks/deploy-app.yml`
installs this chart inside the kubeadm Vagrant VM so authentication
flows can be exercised end-to-end without the Pi services stack.

## If you're editing this chart

- Any change here affects **only Vagrant tests**, not live auth.
- Changes to real production Keycloak live in `ops/deploy/ansible/playbooks/setup-pi-services.yml` (keycloak.service definition) and `platform/helm/schnappy-auth/keycloak-realm-configmap.yaml` is NOT what production reads — production Keycloak bootstrap config is in the bare-metal playbook.

## Why keep it under `helm/` rather than `helm/test/`

Single vagrant task consumes it with a hardcoded path. Moving the
directory would break the test task. README here should be enough
signal for anyone doing a chart audit.
