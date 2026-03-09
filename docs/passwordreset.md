# Emergency Password Reset

Use this procedure when you are locked out of Open WebUI and cannot log in via the UI.

> **This stack uses PostgreSQL** (pgvector). All password reset commands target the `db` container via `psql`.

---

## Standalone (docker compose)

```bash
# 1. Get the db container name
docker ps --filter "name=db" --format "{{.Names}}"

# 2. Generate a bcrypt hash of your new password
docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "YourNewPassword!" | tr -d ':\n' | sed 's/$apr1/$2y/'

# 3. Update the password in PostgreSQL
docker exec -it <db_container> psql -U postgres -d openwebui -c \
  "UPDATE \"user\" SET password = '<bcrypt_hash>' WHERE email = 'your-admin@email.com';"
```

Replace `<db_container>` with the name from step 1 and `<bcrypt_hash>` with the output from step 2 (including the `$2y$...` prefix).

---

## Docker Swarm

In Swarm mode, the database runs as a service. Find the node hosting the `db` task, then use `docker exec` on that node.

```bash
# 1. Find which node the db task is running on
docker service ps ${STACK_NAME:-open-webui}_db

# 2. SSH to that node, then find the container
docker ps --filter "name=${STACK_NAME:-open-webui}_db" --format "{{.Names}}"

# 3. Generate a bcrypt hash of your new password
docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "YourNewPassword!" | tr -d ':\n' | sed 's/$apr1/$2y/'

# 4. Update the database
docker exec -it <db_container> psql -U postgres -d openwebui -c \
  "UPDATE \"user\" SET password = '<bcrypt_hash>' WHERE email = 'your-admin@email.com';"
```

---

## Notes

- The `psql` client is available inside the `pgvector/pgvector:pg17` container.
- The `tools-init` service connects to Open WebUI via the internal overlay network (`http://openwebui:8080`), bypassing Traefik OAuth entirely — so it can still function even when the OAuth chain is broken.
- If Open WebUI is running with `ENABLE_LOGIN_FORM=true` (default in this stack), the login form remains accessible at `http://localhost:3000` even when Traefik OAuth middleware is misconfigured — the form just won't be reachable via the Traefik-proxied domain.
