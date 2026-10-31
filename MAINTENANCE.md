# Maintenance

Playbooks for after the initial [server setup](README.md): installing apps and managing
users. 

This part is far less thought through than the initial server setup. It could be useful to create a different repo for the maintenance parts mentioned here. The idea to [configure all users via a single .yaml file](https://oneuptime.com/blog/post/2026-02-21-how-to-create-ansible-roles-for-user-management/view) also feels better than my current approach.

Run these playbooks like the others, with `sudo ./run-ansible-logged.sh <playbook>`
from the repository folder (see [Running Playbooks](README.md#running-playbooks)
for options and remote use).

## `install-apps-playbook.yml`: apps

Software for your work on the server. 

- Syncthing to sync files between different computers. 
- mise provides dev tools, env vars, and tasks in one CLI.
- Quarto, for documents and reports from Markdown, Python or R. PDF output needs TinyTeX, installed per user: `quarto install tinytex`; `quarto check` shows what else is missing.
- Chromium's system libraries, for Playwright (web automation, AI agents). Playwright and the browser itself are installed per user: `npx playwright install chromium`.
- and other stuff, more to come ...

The general idea here is to install widely used and stable tools from apt, which require sudo.

It asks no questions and runs these roles:

| Role | Tags | What it does |
|---|---|---|
| `install_app_packages` | `packages` | ripgrep, Python build tools, ffmpeg, syncthing |
| `mise` | `packages`, `mise` | mise from mise's own apt repository |
| `quarto` | `packages`, `quarto` | Quarto's `.deb` from GitHub, with a fixed checksum |
| `install_chromium_dependencies` | `packages`, `chromium` | Libraries, fonts and xvfb that Chromium (Playwright) needs |

## `create-user-playbook.yml`: Add more users

Main idea: run different apps as different users (without sudo). Users are isolated from each other: if one runs amok, it can only damage its own files and `/srv/shared`, not other users or the system. Exception: members of the `docker` group can do anything (root).

Creates (or updates) one account and asks for the important decisions, using
the same `user_account` role as the admin.

| Question | Default |
|---|---|
| Give sudo rights? | no |
| Password (`su`, sudo, console; never SSH). Required; empty only keeps an existing one | — |
| Login shell: bash or zsh | bash |
| With sudo: turn the sudo password off completely | no |
| With sudo and a sudo password: hours before sudo asks for it again (per login session) | 24 |
| SSH keys: copy from a user, paste a public key, or `none` | `me`: the user who ran `sudo` (over SSH: `-u`) |
| `docker` group (effectively root) / `adm` group (read logs) | no / no |
| `shared` group: [`/srv/shared`](README.md#shared-folder-srvshared), linked as `~/shared` | no |
| Lingering (systemd user services start at boot) | yes |

At the end it prints a summary of the choices and what they mean. Answers can
also be given on the command line, e.g. `-e username=alice -e sudo=no`.

For an `aiagent` user, [`create-agent-user.sh`](create-agent-user.sh) runs
`create-user-playbook.yml` with fixed answers: `aiagent`, no sudo, bash, `docker` (if the agent is malicious, this implies root access, see [Known trade-offs](security-architecture.md#known-trade-offs)), `adm` and `shared` groups, lingering off, SSH keys copied from you. Only the password is asked:

```bash
sudo ./create-agent-user.sh    # works on server only, not via remote access
```

### Changing a user

Run `create-user-playbook.yml` again with the same username. It changes what the
answers say, but only ever **adds** groups and keys:

| What | Re-running `create-user-playbook.yml` | By hand |
|---|---|---|
| sudo on / off, password timeout, passwordless | changed as answered (no = removed from `sudo`) | — |
| Password | replaced if you enter one; empty keeps it | `sudo passwd <user>` |
| Login shell | changed as answered | `sudo chsh -s /bin/zsh <user>` |
| `docker` / `adm` / `shared` groups | only added, never removed | `sudo gpasswd -d <user> docker` |
| SSH keys | a pasted key is added; copying from another user only seeds a missing `authorized_keys` | edit `~<user>/.ssh/authorized_keys` |
| Lingering | only turned on | `sudo loginctl disable-linger <user>` |

### Deleting a user

The playbooks never delete users. By hand, as the admin:

```bash
# 1. Stop its background services and don't start them at boot anymore
sudo loginctl disable-linger <user>
```

```bash
# 2. End all its running processes (open sessions included)
sudo pkill -u <user>
```

```bash
# 3. Remove the account and its home folder (--remove-all-files: also its files elsewhere)
sudo deluser --remove-home <user>
```

```bash
# 4. Remove its sudo settings, if it had any
sudo rm -f /etc/sudoers.d/90-<user>
```

Docker containers the user started keep running (Docker runs them, not the
user): stop them with `docker compose down` first.
