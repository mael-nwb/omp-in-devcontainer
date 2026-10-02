# omp Devcontainer

Ce dépôt contient une Feature Dev Container « omp-cli » et ses tests automatisés. Elle installe [oh-my-pi (omp)](https://omp.sh/) — un agent de code pour le terminal, fork plus capable de Pi, avec un moteur Rust natif.

## Utilisation (Feature Dev Container)

Pour utiliser la feature dans un `devcontainer.json`:

```json
"features": {
  "./src/omp-cli": {}
}
```

Depuis GHCR après publication, adaptez le chemin au dépôt publié:

```json
"features": {
  "ghcr.io/mael-nwb/omp-in-devcontainer/omp-cli:latest": {}
}
```

La feature installe Bun puis omp via l'installation source officielle (`https://omp.sh/install.sh --source`). Bun sert à la fois de runtime pour le CLI omp installé et pour le petit script de réécriture de config au démarrage (voir ci-dessous).

## Configuration hôte et données du conteneur

La feature déclare elle-même les deux montages nécessaires :

- `${localEnv:HOME}/.omp` vers `/mnt/omp-host`, en **lecture seule**, pour lire la configuration de l'hôte.
- `${localEnv:HOME}/.omp-devcontainer` vers `/home/vscode/.omp-devcontainer`, pour persister les données du conteneur.

Elle expose `OMP_SOURCE_AGENT_DIR=/mnt/omp-host/agent` et `PI_CODING_AGENT_DIR=/home/vscode/.omp-devcontainer/agent`. Il n'est donc pas nécessaire de recopier ces mounts ou ces variables dans le `devcontainer.json` consommateur. La destination de persistance actuelle correspond à l'utilisateur `vscode`.

À chaque démarrage du conteneur (`postStartCommand`) et avant chaque commande `omp`, la feature synchronise la configuration hôte vers le répertoire d'agent du conteneur :

- `config.yml`, `models.yml`, `models.json`, `settings.json`, `auth.json` et `.env` sont remplacés lorsque le fichier existe dans la source.
- `agents/`, `skills/` et `hooks/` sont fusionnés, sans supprimer les fichiers propres au conteneur.
- `sessions/`, les fichiers `*.db`, `cache/`, `blobs/` et `terminal-sessions/` restent propres au conteneur. Les données équivalentes de l'hôte ne sont pas importées.

**La configuration hôte prime à chaque synchronisation.** Les modifications faites dans le conteneur sur les fichiers synchronisés seront remplacées au lancement suivant. Les fichiers absents de la source sont conservés dans le conteneur, et les sélections `enabledModels` de l'hôte sont respectées.

L'ancien seed copiait uniquement vers un dossier vide, une seule fois. Un dossier déjà rempli ou un marqueur `.seeded-from-host` pouvait donc empêcher la récupération de la configuration. Ce marqueur n'est plus utilisé.

La réécriture transforme les URLs HTTP(S) de `localhost`, `127.0.0.1` et `[::1]` vers `host.docker.internal` dans les six fichiers copiés. Elle couvre tous les providers et les formats YAML et JSON, y compris les fichiers JSON avec commentaires. Le remplacement conserve le format du fichier et ne modifie jamais la source hôte. Les URLs distantes et celles utilisant déjà `host.docker.internal` restent inchangées.

La feature exporte aussi `OLLAMA_HOST` et `OLLAMA_BASE_URL` vers `host.docker.internal:11434` pour la découverte implicite Ollama. omp peut ensuite migrer ses fichiers JSON hérités vers YAML (`models.json` vers `models.yml`, `settings.json` vers `config.yml`).

## Préparation initiale sur chaque poste

Avant la première création ou le rebuild du Dev Container, exécutez **sur l'hôte** :

```sh
mkdir -p "$HOME/.omp/agent" "$HOME/.omp-devcontainer/agent"
```

Cette préparation est nécessaire avant les bind mounts. Le script d'installation d'une feature s'exécute dans l'image en construction et ne peut pas créer ces dossiers sur l'hôte. Aucun script de synchronisation OMP ni `initializeCommand` spécifique à OMP n'est nécessaire dans le projet. Si la source hôte ne contient pas de configuration, omp se configure normalement dans le conteneur.

Pour migrer un projet utilisant déjà `init-host-config.sh`, retirez sa copie et sa réécriture OMP ainsi que les mounts et variables OMP redondants. Conservez ses éventuelles autres préparations (Codex, Claude, Pi) et son `initializeCommand` si elles en ont besoin. Un rebuild avec la feature corrigée est nécessaire.

Les montages de feature nécessitent un outil Dev Containers qui prend en charge les métadonnées de features. Avec un moteur Docker distant, leurs chemins source doivent être disponibles sur la machine du moteur.

## Services locaux sur Linux

Docker Desktop fournit `host.docker.internal`. Sur un hôte Linux natif, ajoutez cette résolution au service de votre `docker-compose.yml` :

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Sans Compose, l'équivalent dans `devcontainer.json` est :

```json
"runArgs": ["--add-host=host.docker.internal:host-gateway"]
```

Le service local doit aussi écouter sur une interface accessible au conteneur. Voir la [documentation Docker sur la résolution de l'hôte](https://docs.docker.com/compose/how-tos/networking/#custom-dns-with-extra_hosts).

Des models parasites peuvent également être visibles en fonction de la configuration de votre repo. (aws, openai...)
Pour limiter strictement leur vision, créez un dossier `.omp` à la racine du projet, puis un fichier `config.yml` (ou `settings.json` hérité) qui contient ce type de déclaration :

```yaml
enabledModels:
  - openai-codex/*
  - ollama/*
```

## Tests (Docker)

Construire l'image de test et vérifier que `omp` est présent :

```bash
bash scripts/build_and_test.sh
```

## Structure

- `src/omp-cli/`: Feature locale pour omp CLI
- `test/omp-cli/`: tests de la feature (scénarios + scripts)
- `test/Dockerfile`: exécute l'installation de la feature sur une image sans Bun préinstallé et vérifie la présence de `omp`
- `scripts/build_and_test.sh`: build + run de l'image de test

## Installation via Codex

Collez cette commande dans votre terminal hors du Dev Container. Elle envoie un prompt au CLI Codex pour ajouter la feature omp à votre projet.

```bash
codex "$(cat <<'EOF'
Ajoute la feature omp-cli à mon Dev Container. Crée ou modifie .devcontainer/devcontainer.json pour inclure:
"features": {
  "ghcr.io/mael-nwb/omp-in-devcontainer/omp-cli:latest": {}
}
Prépare sur l'hôte les dossiers nécessaires avant la création du conteneur :
mkdir -p "$HOME/.omp/agent" "$HOME/.omp-devcontainer/agent"
La feature fournit les mounts, les variables OMP et la synchronisation au démarrage.
N'ajoute pas de script de synchronisation OMP ni d'initializeCommand pour cette synchronisation.
Préserve les initializeCommand et mounts nécessaires aux autres outils.
Sur Linux natif, ajoute host.docker.internal:host-gateway avec extra_hosts (Compose)
ou runArgs: ["--add-host=host.docker.internal:host-gateway"] (sans Compose).
EOF
)"
```
