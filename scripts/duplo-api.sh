#!/bin/bash -eu

account="$1" ; shift
export tenant="$account"

# Load environment and utility programs.
# shellcheck disable=SC1091    # VS code won't enable following the files.
source "$(dirname "${BASH_SOURCE[0]}")/_util.sh"
# shellcheck disable=SC1091    # VS code won't enable following the files.
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

duplo_api "$@"
