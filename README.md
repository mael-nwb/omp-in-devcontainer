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

Dans un Dev Container, la commande `omp` utilise `~/.omp-devcontainer/agent` comme répertoire d'agent persistant. La feature déclare le bind mount `${localEnv:HOME}/.omp-devcontainer` vers `/home/vscode/.omp-devcontainer` et expose `PI_CODING_AGENT_DIR=/home/vscode/.omp-devcontainer/agent` au conteneur. Si une configuration hôte est montée dans `~/.omp/agent`, elle est copiée une seule fois dans ce répertoire interne puis isolée. La feature réécrit automatiquement `providers.ollama.baseUrl` de `localhost` vers `host.docker.internal` dans cette copie interne, sans modifier la configuration hôte. Elle exporte aussi `OLLAMA_HOST` / `OLLAMA_BASE_URL` vers `host.docker.internal:11434` pour la découverte implicite Ollama. Lors de cette copie initiale, `settings.json` est aussi nettoyé de `enabledModels`.

omp migre ensuite lui-même les fichiers JSON hérités en YAML au premier lancement (`models.json` → `models.yml`, `settings.json` → `config.yml`).

## Préparation du dossier hôte `.omp-devcontainer`

Le bind mount de feature attend que le dossier hôte `${HOME}/.omp-devcontainer/agent` existe avant la création du conteneur. Ajoutez cette commande côté consommateur dans `.devcontainer/devcontainer.json`:

```json
"initializeCommand": [
  "sh",
  "-lc",
  "touch \"${localEnv:HOME}/.claude-devcontainer.json\"; mkdir -p \"${localEnv:HOME}/.omp-devcontainer/agent\"; :"
]
```

Si votre version de l'outil Dev Containers ne fusionne pas encore les `mounts` ou `containerEnv` déclarés par les features, gardez aussi ces entrées explicites dans le `devcontainer.json` consommateur:

```json
"mounts": [
  "source=${localEnv:HOME}/.omp-devcontainer,target=/home/vscode/.omp-devcontainer,type=bind,consistency=cached"
],
"remoteEnv": {
  "PI_CODING_AGENT_DIR": "/home/vscode/.omp-devcontainer/agent"
}
```

## Configuration omp hôte

Pour réutiliser votre configuration omp locale, le dossier `${HOME}/.omp` doit exister sur l'hôte avant le rebuild du Dev Container.

Ajoutez ensuite ce mount dans le `devcontainer.json` consommateur, en adaptant le home si votre `remoteUser` n'est pas `vscode`:

```json
"mounts": [
  "source=${localEnv:HOME}/.omp,target=/home/vscode/.omp,type=bind,consistency=cached"
]
```

Si `${HOME}/.omp` est absent, la feature installe uniquement le CLI omp. omp devra être configuré après ouverture du conteneur.

La configuration active d'omp dans le conteneur reste `~/.omp-devcontainer/agent`. Le mount hôte sert uniquement de source initiale. Si `/usr/local/bin/omp` est encore un simple symlink ou si `PI_CODING_AGENT_DIR` n'est pas défini dans un shell de login, vous utilisez probablement un artefact GHCR plus ancien et il faut republier / rebuild la feature.

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
Ajoute aussi initializeCommand pour préparer les dossiers hôte avant le mount:
"initializeCommand": [
  "sh",
  "-lc",
  "touch \"${localEnv:HOME}/.claude-devcontainer.json\"; mkdir -p \"${localEnv:HOME}/.omp-devcontainer/agent\"; :"
]
Si les mounts de features ne sont pas appliqués par l'outil Dev Containers utilisé, ajoute aussi:
"mounts": [
  "source=${localEnv:HOME}/.omp-devcontainer,target=/home/vscode/.omp-devcontainer,type=bind,consistency=cached"
],
"remoteEnv": {
  "PI_CODING_AGENT_DIR": "/home/vscode/.omp-devcontainer/agent"
}
EOF
)"
```
