#!/bin/sh
#
# Master of Puppets one-command installer.
#
#   curl -fsSL https://raw.githubusercontent.com/jorgegorka/master-of-puppets/master/scripts/install.sh | sh
#
# Installs Docker if missing (on Linux via get.docker.com; on macOS via
# Homebrew using Colima + the docker CLI, falling back to Docker Desktop only
# if Homebrew is absent), pulls the latest Master of Puppets image from GHCR,
# and runs it on http://localhost:3000 with a persistent volume for SQLite data.

set -eu

IMAGE="${MASTER_OF_PUPPETS_IMAGE:-ghcr.io/jorgegorka/master-of-puppets:latest}"
CONTAINER="${MASTER_OF_PUPPETS_CONTAINER:-master-of-puppets}"
VOLUME="${MASTER_OF_PUPPETS_VOLUME:-master_of_puppets_storage}"
HOST_PORT="${MASTER_OF_PUPPETS_PORT:-3000}"

say() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; exit 1; }

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo linux ;;
    Darwin*) echo darwin ;;
    *)       err "unsupported OS: $(uname -s). Master of Puppets supports Linux and macOS." ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo amd64 ;;
    arm64|aarch64) echo arm64 ;;
    *)             err "unsupported architecture: $(uname -m). Master of Puppets supports amd64 and arm64." ;;
  esac
}

ensure_docker() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    case "$OS" in
      darwin) err "Docker is installed but not running. Start Docker Desktop and re-run this script." ;;
      linux)  err "Docker is installed but not running. Run 'sudo systemctl start docker' and re-run this script." ;;
    esac
  fi

  case "$OS" in
    darwin)
      if command -v brew >/dev/null 2>&1; then
        say "Docker is not installed. Installing Colima + Docker CLI via Homebrew..."
        brew install colima docker

        say "Starting Colima (Docker daemon) ..."
        colima start

        if ! docker info >/dev/null 2>&1; then
          err "Colima started but the Docker daemon is not reachable. Run 'colima status' to investigate."
        fi
        return 0
      fi

      say "Docker is required and Homebrew is not installed."
      say "Either install Homebrew (https://brew.sh) and re-run this script,"
      say "or install Docker Desktop manually from:"
      say "  https://www.docker.com/products/docker-desktop"
      exit 1
      ;;
    linux)
      say "Docker is not installed. Installing via https://get.docker.com ..."
      if [ "$(id -u)" -eq 0 ]; then
        curl -fsSL https://get.docker.com | sh
      else
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER" || true
        say ""
        say "Added $USER to the 'docker' group. That takes effect in a new shell,"
        say "so this run will use 'sudo docker' for the remaining steps."
        DOCKER="sudo docker"
      fi
      ;;
  esac
}

wait_for_ready() {
  attempt=0
  while [ $attempt -lt 60 ]; do
    if curl -fsS "http://localhost:${HOST_PORT}/up" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  return 1
}

main() {
  OS="$(detect_os)"
  ARCH="$(detect_arch)"
  DOCKER="docker"

  say "Installing Master of Puppets for ${OS}/${ARCH}..."
  ensure_docker

  say "Pulling ${IMAGE} ..."
  $DOCKER pull "$IMAGE"

  say "Ensuring storage volume ${VOLUME} ..."
  $DOCKER volume create "$VOLUME" >/dev/null

  if $DOCKER ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    say "Removing previous '${CONTAINER}' container (data in ${VOLUME} is preserved)..."
    $DOCKER rm -f "$CONTAINER" >/dev/null
  fi

  say "Starting Master of Puppets on http://localhost:${HOST_PORT} ..."
  $DOCKER run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    -p "${HOST_PORT}:80" \
    -v "${VOLUME}:/rails/storage" \
    -e MASTER_OF_PUPPETS_STANDALONE=1 \
    "$IMAGE" >/dev/null

  say "Waiting for Master of Puppets to become ready ..."
  if ! wait_for_ready; then
    say ""
    say "Master of Puppets did not become ready within 60 seconds. Recent logs:"
    $DOCKER logs --tail 50 "$CONTAINER" >&2 || true
    err "startup failed"
  fi

  say ""
  say "Master of Puppets is running. Visit http://localhost:${HOST_PORT}"
  say ""
  say "Manage it with:"
  say "  docker logs -f ${CONTAINER}"
  say "  docker stop ${CONTAINER}"
  say "  docker start ${CONTAINER}"
}

main "$@"
