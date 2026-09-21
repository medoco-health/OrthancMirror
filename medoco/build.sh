#!/usr/bin/env bash
#
# Build, tag and optionally push a medoco Orthanc image.
#
#   ./medoco/build.sh 1              # build 1.13.0-medoco.1, locally
#   ./medoco/build.sh 1 --push       # ... and push it, and the git tag
#
# The single argument is the medoco patch level: bump it whenever anything in
# this fork changes, reset it to 1 when rebasing onto a new Orthanc release. The
# Orthanc half of the version is read from the tree, never typed by hand.
#
# See medoco/README.md for the versioning scheme and the release checklist.
set -euo pipefail

REGISTRY=${REGISTRY:-cr.medoco.health/medoco/orthanc}
JOBS=${JOBS:-4}
RELEASE_BRANCH=medoco/main

cd "$(dirname "$0")/.."

usage() {
  echo "usage: $0 <medoco patch level> [--push]" >&2
  echo "   e.g. $0 1        -> ${REGISTRY}:<orthanc version>-medoco.1" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
[[ $1 =~ ^[0-9]+$ ]] || usage
# Anything other than --push is a typo, not a request to build without pushing.
[[ $# -eq 1 || $2 == --push ]] || usage

LEVEL=$1
PUSH=${2:-}

# Build only what is committed. A build from a dirty tree cannot be traced back
# to a commit, which defeats both the version tag and the GPLv3 source label.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash before building." >&2
  git status --short >&2
  exit 1
fi

ORTHANC_VERSION=$(sed -n 's/^set(ORTHANC_VERSION "\(.*\)")$/\1/p' \
  OrthancFramework/Resources/CMake/OrthancFrameworkParameters.cmake)

if [[ -z $ORTHANC_VERSION ]]; then
  echo "Could not read ORTHANC_VERSION from the CMake parameters." >&2
  exit 1
fi

if [[ $ORTHANC_VERSION == mainline ]]; then
  echo "This tree says ORTHANC_VERSION=mainline, so it is not a release." >&2
  echo "Rebase medoco/main onto a release commit first (see medoco/README.md)." >&2
  exit 1
fi

VERSION="${ORTHANC_VERSION}-medoco.${LEVEL}"
REVISION=$(git rev-parse HEAD)
IMAGE="${REGISTRY}:${VERSION}"

# An immutable tag that already exists is either a mistake or a rebuild that
# would silently change what a deployed tag means. Refuse both.
if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  echo "Git tag ${VERSION} already exists. Bump the patch level." >&2
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ $PUSH == --push ]]; then
  # Everything below takes about an hour, so the reasons it could not be
  # published are all checked before any of it starts.

  # The local check above misses a tag pushed from another clone. The image is
  # pushed before the tag, so a clash first noticed at `git push` would already
  # have overwritten that tag in the registry.
  remote_tag=0
  git ls-remote --exit-code --tags origin "refs/tags/${VERSION}" >/dev/null || remote_tag=$?
  if [[ $remote_tag == 0 ]]; then
    echo "Git tag ${VERSION} already exists on origin. Bump the patch level." >&2
    exit 1
  elif [[ $remote_tag != 2 ]]; then
    echo "Could not check origin for tag ${VERSION}; refusing to publish." >&2
    exit 1
  fi
  if [[ $BRANCH != "$RELEASE_BRANCH" ]]; then
    echo "On '${BRANCH}'. Released builds are cut from '${RELEASE_BRANCH}'." >&2
    echo "Build without --push to try this branch out." >&2
    exit 1
  fi

  # Docker stores credentials either inline under "auths" or in a helper named by
  # "credsStore" or "credHelpers", so any of the three counts as evidence of a
  # login. Refuse only when the config exists and shows none of them, and say
  # nothing when there is no config to read: rejecting a valid release after an
  # hour of compiling is a worse outcome than missing the warning.
  DOCKER_CONFIG_FILE=${DOCKER_CONFIG:-$HOME/.docker}/config.json
  if [[ -f $DOCKER_CONFIG_FILE ]] &&
     ! grep -qE "\"credsStore\"|\"credHelpers\"|${REGISTRY%%/*}" "$DOCKER_CONFIG_FILE"; then
    echo "No credentials for ${REGISTRY%%/*} in $DOCKER_CONFIG_FILE." >&2
    echo "Run: docker login ${REGISTRY%%/*}" >&2
    exit 1
  fi
elif [[ $BRANCH != "$RELEASE_BRANCH" ]]; then
  echo "Note: building from '${BRANCH}', not '${RELEASE_BRANCH}'."
fi

echo "Orthanc  : ${ORTHANC_VERSION}"
echo "Version  : ${VERSION}"
echo "Revision : ${REVISION}"
echo "Image    : ${IMAGE}"
echo "Jobs     : ${JOBS}   (expect roughly an hour, ~15 GB of Docker storage)"
echo

# git archive rather than the working directory: the build context is then
# exactly the committed tree, with no .git, no build leftovers and no local edits.
git archive --format=tar HEAD | docker build \
  -f medoco/Dockerfile \
  --build-arg "JOBS=${JOBS}" \
  --build-arg "VERSION=${VERSION}" \
  --build-arg "REVISION=${REVISION}" \
  -t "${IMAGE}" \
  -

echo
echo "Built ${IMAGE}"
docker run --rm "${IMAGE}"

if [[ $PUSH == --push ]]; then
  # Tag only once the image is published. Tagging first would leave a tag behind
  # on a failed push, and the guard above would then refuse the retry.
  docker push "${IMAGE}"
  git tag -a "${VERSION}" -m "medoco Orthanc build ${VERSION}"
  git push origin "${VERSION}"
  echo
  echo "Pushed ${IMAGE} and tagged ${VERSION}."
else
  echo
  echo "Not pushed, and not tagged. To release this build:"
  echo "  docker push ${IMAGE}"
  echo "  git tag -a ${VERSION} -m 'medoco Orthanc build ${VERSION}'"
  echo "  git push origin ${VERSION}"
fi
