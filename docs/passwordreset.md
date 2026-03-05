# Emergency Password Reset

Use this procedure when you are locked out of Open WebUI and cannot log in via the UI.

---

## Standalone (docker compose)

Open WebUI stores its data in a named Docker volume (`owui_data`). The SQLite database is at `/app/backend/data/webui.db` inside the container.

```bash
# 1. Get the container name
docker ps --filter "name=openwebui" --format "{{.Names}}"

# 2. Generate a bcrypt hash of your new password
docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "YourNewPassword!" | tr -d ':\n' | sed 's/$apr1/$2y/'

# 3. Update the password in the database
docker exec -it <container_name> bash -c "
  sqlite3 /app/backend/data/webui.db \
  \"UPDATE user SET password = '<bcrypt_hash>' WHERE email = 'your-admin@email.com';\"
"
```

Replace `<bcrypt_hash>` with the output from step 2 (including the `$2y$...` prefix).

---

## Docker Swarm

In Swarm mode, Open WebUI data lives at `${DATA_ROOT}/open-webui/data/webui.db` on the node where the service is running. Find the node, then use `docker exec` on that node.

```bash
# 1. Find which node the openwebui task is running on
docker service ps open-webui_openwebui

# 2. SSH to that node, then find the container
docker ps --filter "name=open-webui_openwebui" --format "{{.Names}}"

# 3. Generate a bcrypt hash of your new password
docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "YourNewPassword!" | tr -d ':\n' | sed 's/$apr1/$2y/'

# 4. Update the database
docker exec -it <container_name> bash -c "
  sqlite3 /app/backend/data/webui.db \
  \"UPDATE user SET password = '<bcrypt_hash>' WHERE email = 'your-admin@email.com';\"
"
```

---

## Notes

- The `sqlite3` binary is available inside the Open WebUI container.
- The `tools-init` service connects to OWUI via the internal overlay network (`http://openwebui:8080`), bypassing Traefik OAuth entirely — so it can still function even when the OAuth chain is broken.
- If Open WebUI is running with `ENABLE_LOGIN_FORM=true` (default in this stack), the login form remains accessible at `http://localhost:3000` even when Traefik OAuth middleware is misconfigured — the form just won't be reachable via the Traefik-proxied domain.
