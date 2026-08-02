# Caddy reverse proxy

Example script reverse-proxies two hostnames to a backend services. We assume the service should only be reachible via a VPN (minimal changes required if everything is public).

| Site | Port | TLS | HTTP service |
|---|---|---|----|
| `<private-vpn-hostname>` (e.g. a NetBird/Tailscale mesh address) | 80 | none (the VPN tunnel already encrypts it) |  127.0.0.1:`<port>`
| `<your-domain.example>` | 443 | `tls internal` — Caddy's own local CA (also encrypted by VPN tunnel) |  127.0.0.1:`<port>`

Arguments:

- `<private-vpn-hostname>` = e.g., `<xxxx>`.netbird.cloud
- `<your-domain.example>` = Optional, just a toy example and most likely not needed. Point `<your-domain.example>` to `<private-vpn-ip>` (or to `<public-ip>` if everyone should reach the service)

Move files from this directory to .caddy directory.
```
mkdir .caddy
cd .caddy
```

Make all required changes for your setup in the Caddyfile.


Start reverse proxy with
```
docker compose up
```

## Key decisions

- **`network_mode: host`** (docker-compose.yml): Host mode
  puts Caddy in the host netns so it reaches `127.0.0.1:<port>` directly. Doesn't behave like standard containers.
- **`bind <private-vpn-ip>`** (Caddyfile): Security measure: Only handle VPN traffic. NetBird routes traffic to this box over the encrypted WireGuard tunnel, arriving at the wt0 interface addressed to `<private-vpn-ip>`. Default would listen to `0.0.0.0` (i.e. also any public IP the host has).
- Explicit `:80`/`:443` in the Caddyfile site addresses are documentation
  only — Caddy already infers them from the `http://` scheme and from
  automatic HTTPS.
- **`encode @not_sse`** (Caddyfile): compression is skipped on the SSE
  endpoints. Compression buffers bytes to build blocks, which delays the small,
  frequent event and keepalive frames those streams depend on — it shows up as
  stalled or dropped connections. Remove or adapt for your setup.

## Gotcha

- Firewall settings?! Could be complicated.
- Editing `Caddyfile` or `docker-compose.yml` in place and running
`caddy reload` may not pick up the change. Use
`docker restart caddy` after edits to be sure that changes are picked up.
