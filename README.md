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

Dans un Dev Container, la commande `omp` utilise ensuite une copie locale de la configuration dans `~/.omp-devcontainer/agent`. La feature exporte aussi `PI_CODING_AGENT_DIR` vers ce répertoire pour les shells du conteneur (omp honore cette variable). Si une configuration hôte est montée dans `~/.omp/agent`, elle est copiée une seule fois dans ce répertoire interne au conteneur puis isolée. La feature réécrit automatiquement `providers.ollama.baseUrl` de `localhost` vers `host.docker.internal` dans cette copie interne, sans modifier la configuration hôte. Elle exporte aussi `OLLAMA_HOST` / `OLLAMA_BASE_URL` vers `host.docker.internal:11434` pour la découverte implicite Ollama. Lors de cette copie initiale, `settings.json` est aussi nettoyé de `enabledModels` pour éviter une liste de modèles obsolète.

omp migre ensuite lui-même les fichiers JSON hérités en YAML au premier lancement (`models.json` → `models.yml`, `settings.json` → `config.yml`).

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
Et ajoute dans le tableau "mounts" (crée-le s'il n'existe pas) :
"source=${localEnv:HOME}/.omp,target=/home/vscode/.omp,type=bind,consistency=cached"
EOF
)"
```
