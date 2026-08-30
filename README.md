# 📝 Django TODO List App

This is a simple and clean TODO List web application built with **Django**. It allows users to create, manage, and organize tasks with optional deadlines, tags, and completion statuses.

## ⚙️ Technologies

- **Django**
- **Tailwind CSS**

---

## 🚀 Features

- ✅ Mark tasks as complete or incomplete
- 🗓️ Set deadlines
- 🏷️ Add and manage tags for tasks
- ✏️ Edit existing tasks
- ❌ Delete tasks

## 🛠️ Installation

1. Clone the repository or download the project files.
2. Navigate to the project directory.
3. Create and activate a virtual environment:

    ```bash
    python -m venv venv
    source venv/bin/activate  # On Windows: venv\Scripts\activate
    ```

4. Install the dependencies:

    ```bash
    pip install -r requirements.txt
    ```

5. Apply migrations:

    ```bash
    python manage.py migrate
    ```

6. Load sample data (optional):

    ```bash
    python manage.py loaddata fixture_data.json
    ```

7. Run the server:

    ```bash
    python manage.py runserver
    ```
   
## 📁 Fixtures

1. Sample tasks and tags are provided in `fixture_data.json`.
2. You can load the data using the `loaddata` command:

    ```bash
    python manage.py loaddata fixture_data.json
    ```

## ☸️ Kubernetes

The app runs in Kubernetes as a Django/Gunicorn `Deployment` behind an
`Ingress`, backed by a PostgreSQL `StatefulSet`. All configuration is read from
environment variables (see `to_do/settings.py`): non-sensitive values come from
a `ConfigMap`, sensitive ones from a `Secret`.

### Manifests (`k8s/`)

| File | Kind | Purpose |
|------|------|---------|
| `namespace.yaml` | Namespace | `todo` — holds everything below |
| `secret.yaml` | Secret | Django key + Postgres credentials (**git-ignored**) |
| `secret.example.yaml` | Secret | template for `secret.yaml`, placeholders only |
| `configmap.yaml` | ConfigMap | `DEBUG`, `ALLOWED_HOSTS`, DB host/port |
| `postgres-statefulset.yaml` | StatefulSet | PostgreSQL, 1 replica, 1Gi PVC |
| `postgres-service.yaml` | Service (headless) | stable DNS name `postgres` |
| `migrate-job.yaml` | Job | runs `manage.py migrate` once |
| `web-deployment.yaml` | Deployment | Django app, 3 replicas |
| `web-service.yaml` | Service (ClusterIP) | `todo-web:80` → pods `:8000` |
| `ingress.yaml` | Ingress | `todo.local` **and** `http://localhost/` → `todo-web` |
| `hpa.yaml` | HorizontalPodAutoscaler | scale web 3→6 at 70% CPU (optional) |
| `deploy.sh` | script | applies all of the above in order (see [Deploy](#deploy)) |

### Prerequisites

- A running Kubernetes cluster and `kubectl` pointed at it. On Docker Desktop:
  *Settings → Kubernetes → Enable Kubernetes*, wait for `kubectl cluster-info`
  to respond.
- The `baranotik/todo-web:1.0` image. Build it from the repo root:

  ```bash
  docker build -t baranotik/todo-web:1.0 .
  ```

  On Docker Desktop the cluster shares the local Docker daemon, so no registry
  push is needed (the manifests rely on the default `imagePullPolicy:
  IfNotPresent` for a non-`latest` tag). On a remote cluster, `docker push` the
  image and make sure the tag is reachable.
- An **Ingress controller** (see [Ingress controller](#ingress-controller)
  below). Docker Desktop does **not** ship one — it has to be installed once per
  cluster.

### Secret

`k8s/secret.yaml` holds the sensitive values and is **git-ignored** — never
commit it. Create it from the template:

```bash
cp k8s/secret.example.yaml k8s/secret.yaml
# then edit k8s/secret.yaml and fill in real values
```

Required keys (`Secret` name: `todo-secrets`, namespace: `todo`, type `Opaque`):

| Key                 | Description                                              |
|---------------------|--------------------------------------------------------|
| `DJANGO_SECRET_KEY` | Long random string, e.g. `python -c "import secrets; print(secrets.token_urlsafe(50))"` |
| `POSTGRES_USER`     | Database user (`todo`)                                  |
| `POSTGRES_PASSWORD` | Database password                                       |
| `POSTGRES_DB`       | Database name (`todo`)                                  |

Example (`k8s/secret.example.yaml`, placeholder values only):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: todo-secrets
  namespace: todo
type: Opaque
stringData:
  DJANGO_SECRET_KEY: "replace-with-random-secret"
  POSTGRES_USER: "todo"
  POSTGRES_PASSWORD: "replace-with-strong-password"
  POSTGRES_DB: "todo"
```

### Ingress controller

`k8s/ingress.yaml` only *describes* routing rules. The component that reads them
and serves HTTP traffic is the **Ingress controller** — a cluster-wide reverse
proxy that is **not** part of this app and is installed separately, once per
cluster.

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

On Docker Desktop the controller binds to `localhost:80`. The Ingress has two
rules:

- a **catch-all** rule (no host) — so `http://localhost/` reaches the app with
  no extra setup;
- a **named host** `todo.local` — nicer, but the browser needs to resolve it.
  Add this line to your hosts file (`C:\Windows\System32\drivers\etc\hosts` on
  Windows — edit as Administrator, `/etc/hosts` on Linux/macOS):

  ```
  127.0.0.1 todo.local
  ```

### Deploy

Once the [Secret](#secret) exists, run the deploy script — it applies every
manifest in dependency order and waits for each stage:

```bash
bash k8s/deploy.sh                        # app only (assumes an ingress controller is present)
bash k8s/deploy.sh --ingress-controller   # also install ingress-nginx first
bash k8s/deploy.sh --hpa                  # also apply the HorizontalPodAutoscaler
bash k8s/deploy.sh --delete               # tear down: delete the whole "todo" namespace
```

The script is idempotent — re-run it to roll out a new image or config change.

<details>
<summary>What the script does, step by step</summary>

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml -f k8s/configmap.yaml

kubectl apply -f k8s/postgres-statefulset.yaml -f k8s/postgres-service.yaml
kubectl wait -n todo --for=condition=ready pod -l app=postgres --timeout=120s

kubectl delete job todo-migrate -n todo --ignore-not-found
kubectl apply -f k8s/migrate-job.yaml
kubectl wait -n todo --for=condition=complete job/todo-migrate --timeout=120s

kubectl apply -f k8s/web-deployment.yaml -f k8s/web-service.yaml
kubectl rollout status -n todo deployment/todo-web

kubectl apply -f k8s/ingress.yaml
```

</details>

> Do **not** run `kubectl apply -f k8s/` (the whole directory): it would also
> apply `secret.example.yaml`, which shares the name `todo-secrets` and would
> overwrite your real `secret.yaml` with placeholder values. The script applies
> files explicitly and by name.

### Verify

```bash
kubectl get all,ingress,pvc -n todo
kubectl get pods -n todo -o wide            # postgres-0 + 3x todo-web, all Running / READY
kubectl logs -n todo deploy/todo-web --tail=20
kubectl get ingress -n todo                 # HOSTS, ADDRESS set

curl http://localhost/                      # via the catch-all Ingress rule — HTML of the task list
curl http://todo.local/                     # via the named host — needs the hosts entry
```

If the Ingress controller is not available, reach a pod directly with a
port-forward (pick any free local port — `8080` is often taken):

```bash
kubectl port-forward -n todo svc/todo-web 8888:80
# then open http://localhost:8888/
```

### Common operations

```bash
# follow web logs
kubectl logs -n todo -l app=todo-web -f --tail=50

# shell / Django management commands inside a running pod
kubectl exec -n todo -it deploy/todo-web -- bash
kubectl exec -n todo -it deploy/todo-web -- python manage.py createsuperuser
kubectl exec -n todo -it deploy/todo-web -- python manage.py shell

# psql into the database
kubectl exec -n todo -it postgres-0 -- psql -U todo -d todo

# restart all web pods (picks up config changes)
kubectl rollout restart -n todo deploy/todo-web

# manual scale (only if the HPA is not applied)
kubectl scale -n todo deploy/todo-web --replicas=5
```

**Ship a new version of the app:**

```bash
docker build -t baranotik/todo-web:1.1 .
# docker push baranotik/todo-web:1.1        # remote cluster only
kubectl set image -n todo deploy/todo-web todo-web=baranotik/todo-web:1.1
kubectl rollout status -n todo deploy/todo-web
```

**Re-run migrations** (after adding migration files and rebuilding the image) —
a finished Job cannot be re-applied, delete it first:

```bash
kubectl delete job todo-migrate -n todo
kubectl apply -f k8s/migrate-job.yaml
kubectl wait -n todo --for=condition=complete job/todo-migrate --timeout=120s
```

### Autoscaling (HPA)

`k8s/hpa.yaml` scales `todo-web` between 3 and 6 replicas, targeting 70% of the
pod's CPU request (`100m` → target `70m` average). It needs **metrics-server**:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Docker Desktop: metrics-server needs to skip kubelet TLS verification
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl top pods -n todo                    # should print CPU/MEM once it's up
kubectl apply -f k8s/hpa.yaml
kubectl get hpa -n todo -w                  # TARGETS e.g. "cpu: 2%/70%"
```

> When the HPA owns the Deployment, drop `spec.replicas` from
> `web-deployment.yaml` (or expect a brief reset to 3 on every re-apply before
> the HPA corrects it). Here `minReplicas` equals the current `replicas: 3`, so
> the effect is only visible after the HPA has scaled up.

### Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `todo-web` pods stuck `0/1 Running` | readiness probe fails — check the `Host: todo.local` header is set and `todo.local` is in `DJANGO_ALLOWED_HOSTS` |
| Pods `CrashLoopBackOff` | DB unreachable or migrations not run — check `kubectl logs`, confirm `todo-migrate` completed |
| `todo-migrate` retries / fails | Postgres not ready yet — it retries up to `backoffLimit: 3`; check `postgres-0` logs |
| `todo.local` → `DNS_PROBE_FINISHED_NXDOMAIN` | missing `127.0.0.1 todo.local` in hosts — or just use `http://localhost/` |
| `http://localhost/` → connection refused | Ingress controller not installed / not ready |
| Ingress `404` from nginx | `ingressClassName` mismatch, or the Ingress is in a different namespace than expected |
| `kubectl get hpa` shows `<unknown>/70%` | metrics-server missing or not ready |
| `ImagePullBackOff` | image not built locally (Docker Desktop) or not pushed (remote cluster) |

### Teardown

```bash
bash k8s/deploy.sh --delete                 # deletes the "todo" namespace and everything in it
```

This removes the PVC too, so the database data is lost. The ingress-nginx
controller is cluster-wide and left in place; remove it separately if needed:

```bash
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```