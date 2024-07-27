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
declare -Agx PROFILE

PROFILE["STARTTIME"]="$(date +%s.%N)"

source /usr/local/bin/scripts/utils.sh || { echo "::error::Unable to load dependency '/usr/local/bin/scripts/utils.sh'"; exit 1; }

trap 'rm::errorHandler "LINENO" "BASH_LINENO" "${BASH_COMMAND}" "${?}"' ERR

#-------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------
declare -Agx LOGGED_COMMITS
declare -Agx FILTERED_COMMITS

declare -agx COMMITS
declare -agx TYPES

declare -gx _VERSION
declare -gx LOGGED_TYPES
declare -gx USER_NAME
declare -gx USER_EMAIL

declare -gx cfgFile
declare -gx cfgDefault

#-------------------------------------------------------------------
# Process Inputs
#-------------------------------------------------------------------
#while true
#do
#	case "$BUMP_TYPE" in
#		first)
#			;;
#		version)
#			[[ -z "$RELEASE_VERSION" ]] && rm::errorExit "BUMP_TYPE='Version', but no release version specified"
#			[[ "$RELEASE_VERSION" =~ ^[0-9]+\.*[0-9]*\.*[0-9]*$ ]] || rm::errorExit "Invalid release version format"
#			;;
#		patch|minor|major)
#			;;
#		*)
#			export BUMP_TYPE="auto";;
#
#	esac
#done

#-------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------
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
