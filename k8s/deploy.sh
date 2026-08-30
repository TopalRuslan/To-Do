#!/usr/bin/env bash
#
# Deploy the To-Do app to Kubernetes, applying the manifests in dependency order
# and waiting for each stage before moving on.
#
# Usage:
#   bash k8s/deploy.sh [options]
#
# Options:
#   --ingress-controller   install the ingress-nginx controller first (once per cluster)
#   --hpa                  also apply the HorizontalPodAutoscaler (needs metrics-server)
#   --wait-timeout DUR     timeout for readiness waits (default: 120s)
#   --delete               delete the whole "todo" namespace and exit
#   -h, --help             show this help

set -euo pipefail

NS=todo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_NGINX_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml"

WAIT_TIMEOUT=120s
WITH_INGRESS_CONTROLLER=0
WITH_HPA=0
DELETE=0

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^#\s\{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ingress-controller) WITH_INGRESS_CONTROLLER=1 ;;
    --hpa)                WITH_HPA=1 ;;
    --wait-timeout)       WAIT_TIMEOUT="${2:?--wait-timeout needs a value}"; shift ;;
    --delete)             DELETE=1 ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

# --- preflight -------------------------------------------------------------
command -v kubectl >/dev/null || { echo "kubectl not found in PATH" >&2; exit 1; }
kubectl cluster-info >/dev/null 2>&1 || {
  echo "cannot reach a Kubernetes cluster - is it running?" >&2; exit 1;
}

if [ "$DELETE" -eq 1 ]; then
  step "Deleting namespace $NS"
  kubectl delete namespace "$NS" --ignore-not-found
  echo "(the ingress-nginx controller, if installed, is left in place)"
  exit 0
fi

if [ ! -f "$SCRIPT_DIR/secret.yaml" ]; then
  echo "missing $SCRIPT_DIR/secret.yaml" >&2
  echo "  cp k8s/secret.example.yaml k8s/secret.yaml   # then fill in real values" >&2
  exit 1
fi

step "Target cluster: $(kubectl config current-context)"

# --- ingress controller (optional) --------------------------------------------
if [ "$WITH_INGRESS_CONTROLLER" -eq 1 ]; then
  step "Installing ingress-nginx controller"
  kubectl apply -f "$INGRESS_NGINX_URL"
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
fi

# --- namespace + configuration ----------------------------------------------
step "Namespace and configuration"
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/secret.yaml" -f "$SCRIPT_DIR/configmap.yaml"

# --- database --------------------------------------------------------------
step "PostgreSQL"
kubectl apply -f "$SCRIPT_DIR/postgres-statefulset.yaml" -f "$SCRIPT_DIR/postgres-service.yaml"
kubectl -n "$NS" wait --for=condition=ready pod -l app=postgres --timeout="$WAIT_TIMEOUT"

# --- migrations ----------------------------------------------------------------
step "Database migrations"
kubectl -n "$NS" delete job todo-migrate --ignore-not-found
kubectl apply -f "$SCRIPT_DIR/migrate-job.yaml"
if ! kubectl -n "$NS" wait --for=condition=complete job/todo-migrate --timeout="$WAIT_TIMEOUT"; then
  echo "migration job did not complete - logs:" >&2
  kubectl -n "$NS" logs job/todo-migrate --tail=50 >&2 || true
  exit 1
fi

# --- web app --------------------------------------------------------------
step "Web app"
kubectl apply -f "$SCRIPT_DIR/web-deployment.yaml" -f "$SCRIPT_DIR/web-service.yaml"
kubectl -n "$NS" rollout status deployment/todo-web --timeout="$WAIT_TIMEOUT"

# --- ingress -------------------------------------------------------------------
step "Ingress"
kubectl apply -f "$SCRIPT_DIR/ingress.yaml"

# --- hpa (optional) ----------------------------------------------------------
if [ "$WITH_HPA" -eq 1 ]; then
  step "HorizontalPodAutoscaler"
  kubectl apply -f "$SCRIPT_DIR/hpa.yaml"
  kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1 \
    || echo "note: metrics-server not found - the HPA will read <unknown> until it is installed"
fi

step "Done"
kubectl -n "$NS" get pods,svc,ingress
echo
echo "open http://todo.local/   (needs '127.0.0.1 todo.local' in your hosts file)"
