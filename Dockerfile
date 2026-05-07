# Dockerfile pour l'agent BeeBoop en mode sidecar Docker compose.
#
# Pattern "wrapper" : ne contient PAS le code source Go. Pull le binaire
# pre-compile depuis releases.beeboop.net (la meme source que les users
# self-hosted via curl get.beeboop.net/install).
#
# Avantage : un seul artefact a maintenir (le binary linux-amd64), 0
# duplication de pipeline. Cette image n'est qu'un wrapping container
# autour du binaire existant.
#
# Pre-requis : le binaire agent v$AGENT_VERSION doit avoir ete publie sur
# releases.beeboop.net AVANT le build de cette image. Le workflow GHA
# passe AGENT_VERSION = git tag (donc images et binaires sont en sync 1:1).

FROM debian:bookworm-slim

# Version exacte du binaire agent a embarquer. Passee par GHA en build-arg
# depuis le tag git (v1.0.0 -> AGENT_VERSION=1.0.0). On pin pour la
# reproductibilite : `docker build` au meme tag = meme contenu.
ARG AGENT_VERSION=latest

# wal-g version : pinne aussi pour reproductibilite. Releases sur
# https://github.com/wal-g/wal-g/releases.
ARG WALG_VERSION=v3.0.5

# Pull les dependances runtime + l'agent + wal-g en une seule layer
# pour minimiser l'image finale (~80 MB).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        postgresql-client \
    # ── Agent BeeBoop (depuis releases.beeboop.net) ───────────────
    && curl -fsSL "https://releases.beeboop.net/agent/${AGENT_VERSION}/dbtm-agent-linux-amd64.tar.gz" -o /tmp/agent.tar.gz \
    && tar -xzf /tmp/agent.tar.gz -C /tmp \
    && mv /tmp/dbtm-agent-linux-amd64 /usr/local/bin/beeboop-agent \
    && chmod +x /usr/local/bin/beeboop-agent \
    && rm /tmp/agent.tar.gz \
    # ── wal-g binary ──────────────────────────────────────────────
    && curl -fsSL "https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/wal-g-pg-ubuntu-22.04-amd64.tar.gz" -o /tmp/wal-g.tar.gz \
    && tar -xzf /tmp/wal-g.tar.gz -C /tmp \
    && mv /tmp/wal-g-pg-ubuntu-22.04-amd64 /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g \
    && rm /tmp/wal-g.tar.gz \
    # ── Cleanup pour reduire la taille ────────────────────────────
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# User non-root pour reduire la surface attaque.
RUN useradd -r -u 10042 -s /sbin/nologin beeboop \
    && mkdir -p /var/lib/beeboop \
    && chown beeboop:beeboop /var/lib/beeboop
USER beeboop

# Mode sidecar par defaut. Le binaire lit BEEBOOP_AGENT_MODE pour confirmer
# (override possible via env si l'user veut tester un autre mode).
ENV BEEBOOP_AGENT_MODE=sidecar

# Healthcheck : verifie que le postgres voisin du compose repond.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pg_isready -h "${BEEBOOP_POSTGRES_HOST:-postgres}" -p "${BEEBOOP_POSTGRES_PORT:-5432}" -U "${BEEBOOP_POSTGRES_USER:-beeboop_replication}" || exit 1

ENTRYPOINT ["/usr/local/bin/beeboop-agent"]
