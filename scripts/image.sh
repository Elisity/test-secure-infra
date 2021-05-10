#!/bin/bash -eu

# Get command-line arguments, but don't process yet.
cmd="$1" ; shift
svc="${1:-aws_lambda_deploy-service}"
[ $# -eq 0 ] || shift

# Get information specific to git
: "${GITHUB_SHA=$(git rev-parse HEAD)}"
: "${GITHUB_SHORT_SHA=$(git rev-parse --short HEAD)}"
: "${GITHUB_REF=$(git rev-parse --abbrev-ref HEAD)}"
: "${GITHUB_TAG=$(git describe --exact-match --tags "$(git log -n1 --pretty='%h')" 2>/dev/null)}"

# AWS defaults
: "${AWS_DEFAULT_REGION=us-east-2}"
: "${AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)}"

# Determine the branch, commit and image version
: "${GITHUB_WORKFLOW=}"
: "${IMAGE_VERSION=$GITHUB_SHA}"
: "${IMAGE_EXTRA_VERSION="${GITHUB_TAG:-latest}"}"

# Determine the image name and full repository name
image_name="${svc}"
image_registry="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
image_repo="$image_registry/$image_name"

# Building a docker image.
docker_build() {
  (cd "docker/$svc" &&
    docker build \
      --label "git-commit=$GITHUB_SHA" \
      --label "git-ref=$GITHUB_REF" \
      --label "app-version=$IMAGE_EXTRA_VERSION" \
      --network=host \
      -t "$image_name:$IMAGE_VERSION" \
      -t "$image_name:$IMAGE_EXTRA_VERSION" \
      -t "$image_repo:$IMAGE_VERSION" \
      -t "$image_repo:$IMAGE_EXTRA_VERSION" \
      .
    )
}

# Pushing a docker image.
docker_push() {
  docker push "$image_repo:$IMAGE_VERSION"
  docker push "$image_repo:$IMAGE_EXTRA_VERSION"
}

# Logging in to the registry.
docker_login() {
  aws ecr get-login-password | docker login --username AWS --password-stdin "$image_registry"
}

case "$cmd" in
build)
  docker_build
  ;;
push)
  docker_login
  docker_push
  ;;
*)
  echo "$0: unsupported command: $cmd $svc" 1>&2
  exit 1
  ;;
esac
