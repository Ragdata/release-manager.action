#!/usr/bin/env bash
# shellcheck disable=SC2154
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

trap 'err::errHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

git config --global --add safe.directory "$GITHUB_WORKSPACE"
#-------------------------------------------------------------------
# Dependencies
#-------------------------------------------------------------------
source /usr/local/bin/scripts/vars.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/vars.sh'"; exit 1; }
source /usr/local/bin/scripts/utils.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/utils.sh'"; exit 1; }

#-------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------
echo "::group::📑 Configuring Release Manager"
rm::getCurrentVersion
rm::checkConfig
rm::readConfig "$cfgFile"
rm::checkGit
echo "::endgroup::"

echo "::group::📝 Processing Input Variables"
rm::getInputs
echo "::endgroup::"

echo "::group::💾 Gathering Project Data"
rm::getTags
rm::getReleaseTag
rm::checkBranch
echo "::endgroup::"

#-------------------------------------------------------------------
# Write Job Summary
#-------------------------------------------------------------------
summaryTable="
| Variable	   | Value		    |
|:-------------|:--------------:|
"

cat << EOF >> "$GITHUB_STEP_SUMMARY"
### :gift: Ragdata's Release Manager Action Summary
$summaryTable
EOF

exit 0
