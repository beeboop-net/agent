# Dockerfile pour l'agent BeeBoop en mode sidecar Docker compose.
#
# Pattern "wrapper" : ne contient PAS le code source Go. Pull le binaire
# pre-compile depuis releases.beeboop.net (la meme source que les users
# self-hosted via curl get.beeboop.net/install).
#
# Pre-requis : le binaire agent v$AGENT_VERSION variant=$AGENT_VARIANT doit
# avoir ete publie sur releases.beeboop.net AVANT le build de cette image.
# Le workflow GHA build-docker du repo beeboop-net/agent passe ces 2 build
# args depuis le tag git + sa matrice de profils (cf. release.yml).
#
# ── Granularite par-module (defense en profondeur) ────────────────────
# Le binaire embarque dans l'image est compile avec EXACTEMENT les build
# tags Go correspondant au profil (cf. AgentRelease::PROFILES cote SaaS) :
#
#   profil           build tags Go                     -> capabilities
#   ─────────────    ─────────────────────────────     ─────────────────
#   readonly         (aucun)                           backup uniquement
#   sql-read         module_sql_read                   + SQL SELECT
#   sql-rw           sql_read+sql_write                + SQL INSERT/UPDATE/DELETE
#   sql-admin        sql_read+sql_write+sql_ddl        + SQL DDL
#   ssh              module_ssh                        + Terminal SSH
#   sql-read-ssh     sql_read+ssh                      + SQL R + SSH
#   sql-rw-ssh       sql_read+sql_write+ssh            + SQL R/W + SSH
#   full             les 4                             tout
#
# Une SaaS compromise ne peut PAS activer un module hors tags compiles —
# le code n'est pas dans le binaire.

FROM debian:bookworm-slim

# Version exacte du binaire agent a embarquer. Passee par GHA en build-arg
# depuis le tag git (v1.0.0 -> AGENT_VERSION=1.0.0). Pin pour la
# reproductibilite : `docker build` au meme tag = meme contenu.
ARG AGENT_VERSION=latest

# Profil agent (cf. matrice ci-dessus). Default 'readonly' = surface
# d'attaque minimale. Le workflow build-docker boucle sur les 8 profils
# et publie une image taggee par profil.
ARG AGENT_VARIANT=readonly

# wal-g version : pinne aussi pour reproductibilite. Releases sur
# https://github.com/wal-g/wal-g/releases.
ARG WALG_VERSION=v3.0.5

# Pull les dependances runtime + l'agent + wal-g en une seule layer
# pour minimiser l'image finale (~80 MB).
#
# Note URL : on pull le binaire suffixe par profil (dbtm-agent-<profile>-
# linux-amd64.tar.gz) ce qui correspond au filename publie cote SaaS par le
# pipeline backup-restore deploy.yml. Le binaire INTERIEUR au tarball garde
# le nom historique 'dbtm-agent-linux-amd64' pour ne pas casser le mv qui
# suit (alignement avec ComposeYamlEnricher cote SaaS).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        postgresql-client \
    # ── Agent BeeBoop (depuis releases.beeboop.net, profil parametre) ──
    && curl -fsSL "https://releases.beeboop.net/agent/${AGENT_VERSION}/dbtm-agent-${AGENT_VARIANT}-linux-amd64.tar.gz" -o /tmp/agent.tar.gz \
    && tar -xzf /tmp/agent.tar.gz -C /tmp \
    && mv /tmp/dbtm-agent-linux-amd64 /usr/local/bin/beeboop-agent \
    && chmod +x /usr/local/bin/beeboop-agent \
    && rm /tmp/agent.tar.gz \
    # ── wal-g binary ───────────────────────────────────────────────────
    && curl -fsSL "https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/wal-g-pg-ubuntu-22.04-amd64.tar.gz" -o /tmp/wal-g.tar.gz \
    && tar -xzf /tmp/wal-g.tar.gz -C /tmp \
    && mv /tmp/wal-g-pg-ubuntu-22.04-amd64 /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g \
    && rm /tmp/wal-g.tar.gz \
    # ── Cleanup pour reduire la taille ─────────────────────────────────
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

# Label le profil compile pour traceabilite a posteriori (`docker inspect`).
# Permet aux operateurs de verifier d'un coup d'oeil quels modules le
# binaire de cette image supporte.
LABEL net.beeboop.agent.variant="${AGENT_VARIANT}"
LABEL net.beeboop.agent.version="${AGENT_VERSION}"

# Healthcheck : verifie que le postgres voisin du compose repond.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pg_isready -h "${BEEBOOP_POSTGRES_HOST:-postgres}" -p "${BEEBOOP_POSTGRES_PORT:-5432}" -U "${BEEBOOP_POSTGRES_USER:-beeboop_replication}" || exit 1

ENTRYPOINT ["/usr/local/bin/beeboop-agent"]
