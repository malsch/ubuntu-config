# Docker Compose — Cheat Sheet

Run all commands from the directory containing your `docker-compose.yml`.

`<service>` below is the service name as written in that file — not the image
and not the container name. In this repo the Caddy stack defines `caddy`.
Omit it entirely and the command applies to every service in the file.

```bash
docker compose config --services   # list the service names defined here
docker compose config              # render the final config (catches YAML/env mistakes)
```

## Starting & stopping

```bash
docker compose up -d               # start in the background (detached)
docker compose up -d --build       # rebuild images first (for a local Dockerfile)
docker compose restart             # restart (e.g. after editing config)
docker compose stop                # stop without removing
docker compose start               # start an existing stopped container
docker compose down                # stop and remove containers + network
docker compose down -v             # …and delete named volumes — destroys persistent data
```

## Updating

```bash
docker compose pull                # fetch the latest images
docker compose up -d --pull always # fetch and start in a single step
```

## Watching it

```bash
docker compose ps                  # running? which ports?
docker compose logs -f             # follow live logs (all services)
docker compose logs -f --tail 100 <service>   # last 100 lines of one service, then follow
docker stats                       # live CPU / memory / network usage
```

## Looking inside

```bash
docker compose exec <service> sh   # interactive shell (try bash if sh isn't present)
docker compose exec <service> env  # the env it's actually running with
docker compose exec <service> ls /path/to/mount   # peek at a mounted volume
```

## Notes

- **`restart: unless-stopped`** — the container comes back automatically after a reboot or crash, *unless* you explicitly ran `stop` or `down`. After `down`, you must `up -d` again.
- **Config is read at container start.** Editing `docker-compose.yml`, an `.env`, or a bind-mounted config file does nothing until you `restart` (or `up -d`) — and a few images need a full recreate rather than a restart to pick changes up.
- **`down` keeps named volumes; `down -v` deletes them.** Anything you need to survive a teardown belongs in a named volume or a bind mount, not the container filesystem.
- **Published ports bypass UFW.** `-p 8080:80` is reachable from the internet even with a deny-all host firewall. Bind to localhost (`127.0.0.1:8080:80`) or don't publish at all.
