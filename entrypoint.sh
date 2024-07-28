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

#-------------------------------------------------------------------
# Initialisation
#-------------------------------------------------------------------
declare -Ax PROFILE

PROFILE["STARTTIME"]="$(date +%s.%N)"

trap 'err::errorHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

#-------------------------------------------------------------------
# Dependencies
#-------------------------------------------------------------------
source /usr/local/bin/scripts/vars.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/vars.sh'"; exit 1; }
source /usr/local/bin/scripts/utils.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/utils.sh'"; exit 1; }

#-------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------
echo "::group::⭐ Get Current Version Information from Git"
rm::getCurrentVersion
echo "::endgroup::"

echo "::group::📝 Processing Input Variables"
rm::getInputs
echo "::endgroup::"

echo "::group::🔧 Reading Release Manager Configuration"
rm::getConfig
echo "::endgroup::"

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
