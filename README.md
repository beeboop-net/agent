# BeeBoop Agent

Composant client du service [BeeBoop DB Time Machine](https://beeboop.net) —
agent autonome déployé sur les serveurs des clients pour gérer la
sauvegarde continue (WAL streaming via wal-g), la restauration
granulaire, la détection d'anomalies et la communication chiffrée avec
le SaaS BeeBoop.

## Installation

L'installation se fait depuis le SaaS BeeBoop, pas depuis ce repo :

\`\`\`bash
curl -fsSL https://get.beeboop.net/install | sudo bash -s -- --token=<VOTRE_TOKEN>
\`\`\`

Le token se génère depuis votre dashboard BeeBoop, page **Instances**.

## Mode sidecar Docker

Pour les déploiements multi-container (compose), l'image officielle est
publiée sur GHCR :

\`\`\`yaml
services:
  agent:
    image: ghcr.io/beeboop-net/agent:v1
    environment:
      BEEBOOP_AGENT_TOKEN: <token>
      BEEBOOP_POSTGRES_HOST: db
      # ...
\`\`\`

Voir `docker-compose.example.yml` pour un exemple complet.

## Licence

Logiciel propriétaire BeeBoop. Voir [LICENSE](./LICENSE).

## Support

- Documentation : https://beeboop.net/docs
- Contact : support@beeboop.net
