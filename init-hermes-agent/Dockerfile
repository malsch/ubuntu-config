FROM ubuntu:26.04

ARG USER_UID=1001
ARG USER_GID=1001

RUN apt-get update  \
    && apt-get -y --no-install-recommends install  \
        # install any other dependencies you might need
        sudo curl git ca-certificates build-essential systemd \
    && rm -rf /var/lib/apt/lists/*

RUN groupmod -g ${USER_GID} ubuntu \
    && usermod  -u ${USER_UID} -g ${USER_GID} ubuntu \
    && usermod  -aG adm ubuntu \
    # Rename the base image's default "ubuntu" user/group to "aiagent" so it
    # matches the host account (same UID/GID — this is a rename, not a new
    # identity). Must happen before the home dir is (re)populated below.
    && groupmod -n aiagent ubuntu \
    && usermod  -l aiagent -d /home/aiagent -m ubuntu \
    # Pre-create the parents of the bind-mounted mise dirs. Docker creates any
    # missing mount-point parents as root at container start, which would leave
    # ~/.local unwritable and break mise's state dir (~/.local/state/mise).
    # Also add ubuntu user to the adm group (make it capable of reading host logs)
    && mkdir -p /home/aiagent/.local/share \
                /home/aiagent/.local/state/mise \
                /home/aiagent/.config \
    && chown -R ${USER_UID}:${USER_GID} /home/aiagent

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Must match the host's mise location: the shims bind-mounted from the host at
# ~/.local/share/mise/shims are symlinks to the host's mise binary path.
ENV MISE_INSTALL_PATH="/usr/bin/mise"
RUN curl https://mise.run | sh

USER aiagent
ENV PATH="/home/aiagent/.local/share/mise/shims:${PATH}"


 



