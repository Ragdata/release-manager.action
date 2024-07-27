#!/usr/bin/env bash
# shellcheck disable=SC2317
####################################################################
# entrypoint.sh
####################################################################
# Release Manager Docker Action Entrypoint
#
# File:         entrypoint.sh
# Author:       Ragdata
# Date:         26/07/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################

set -eEuo pipefail

shopt -s inherit_errexit

IFS=$'\n\t'	# set unofficial strict mode @see: http://redsymbol.net/articles/unofficial-bash-strict-mode/

source scripts/utils.sh

####################################################################
# MAIN
####################################################################
trap 're::errorHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR


#-------------------------------------------------------------------
# Write Job Summary
#-------------------------------------------------------------------
summaryTable="
| Function	   | Result		  |
| ------------ | :----------: |
"

cat << EOF >> "$GITHUB_STEP_SUMMARY"
### :gift: Ragdata's Release Manager Action Summary
$summaryTable
EOF

exit 0
