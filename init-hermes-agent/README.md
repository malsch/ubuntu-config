# init-hermes-agent

Installs and configures [Hermes](https://hermes-agent.nousresearch.com/) and the
[hermes-webui](https://github.com/nesquena/hermes-webui) frontend.

It includes a Docker sandbox for the agent's terminal tool.

| File | Run as | What it does |
|---|---|---|
| [`setup-hermes.sh`](setup-hermes.sh) | `aiagent` | Installation walkthrough — dependencies, the Hermes installer, Playwright's Chromium libraries, gateway and webui as systemd user services. |
| [`config.yaml.template`](config.yaml.template) | — | A full worked `~/.hermes/config.yaml`. |
| [`Dockerfile`](Dockerfile) | — | Sandbox development image (`mise-dev`) for the agent's terminal tool. |
| [`.dockerignore`](.dockerignore) | — | Keeps `.git` and secrets out of build contexts. |

## `setup-hermes.sh`

A sequence to read and adapt, not a script to pipe into bash — a few lines are
deliberately incomplete (e.g. the `sudo apt install <output>` that takes its
package list from the preceding `playwright install-deps --dry-run`). The webui
portion at the bottom (systemd unit, `enable-linger`, health check) does run as
written once the paths at the top of that block match your box.

## `config.yaml.template`

Two things worth knowing:

- **The terminal tool runs in Docker**, in the `mise-dev` image, with the host's
  mise installation bind-mounted read-only so container and host share tool
  versions. The Dockerfile renames the base image's `ubuntu` user to `aiagent`
  at the host's UID/GID so bind-mounted files keep their ownership.
- **Toolsets, skills, and plugins are aggressively disabled.** The long
  `disabled:` lists are the point, not noise — they keep the model's context
  small and the attack surface narrow.

Config and data live in `~/.hermes` (git-initialized there, most of it ignored),
deliberately outside this repo.

Day-to-day commands: [`../cheatsheets/hermes-cli.md`](../cheatsheets/hermes-cli.md).
