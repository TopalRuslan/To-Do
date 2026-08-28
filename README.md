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

Manifests live in `k8s/`. The app reads its configuration from environment
variables (see `to_do/settings.py`): non-sensitive values come from a
`ConfigMap`, sensitive ones from a `Secret`.

### Secret

`k8s/secret.yaml` holds the sensitive values and is **git-ignored** — never
commit it. Use `k8s/secret.example.yaml` as a template:

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

Apply:

```bash
kubectl apply -f k8s/secret.yaml
kubectl get secret todo-secrets -n todo
```