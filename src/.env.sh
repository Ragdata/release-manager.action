#!/usr/bin/env bash
# shellcheck disable=SC2317
####################################################################
# .env.sh
####################################################################
# Release Manager Docker Action - Environment Variables
#
# File:         .env.sh
# Author:       Ragdata
# Date:         11/08/2024
# License:      MIT License
# Copyright:    Copyright © 2024 Redeyed Technologies
####################################################################
declare -Ax REPO PREV_RELEASE
declare -Ax CURRENT_RELEASE IN_RELEASE RELEASE_VERSION
declare -ax HEADERS RELEASES SEARCH_DIRS LOGGED_TYPES LOGGED_SCOPES BRANCHES

declare -x REPO_NAME REPO_DESC COPYRIGHT WEBSITE REPO_URL REPO_DEFAULT_BRANCH
declare -x OWNER_LOGIN OWNER_ID OWNER_LOCATION OWNER_COMPANY OWNER_BLOG OWNER_TWITTER
declare -x GIT_USER_NAME GIT_USER_EMAIL
declare -x BRANCH_PROD BRANCH_STAGE BRANCH_PATCH BRANCH_RELEASE BRANCH_CURRENT BRANCH_SOURCE
declare -x DATE_FORMAT_SHORT DATE_FORMAT_LONG DATE_FORMAT_DTG
declare -x MESSAGE_COMMIT MESSAGE_RELEASE
declare -x CHANGELOG_TEMPLATE CHANGELOG_TEMPLATE_DEFAULT CHANGELOG_FILE CHANGELOG_STYLE CHANGELOG_CREATE
declare -x RELEASE_TEMPLATE RELEASE_TEMPLATE_DEFAULT RELEASE_CREATE
declare -x PULL_REQUEST_TEMPLATE PULL_REQUEST_TEMPLATE_DEFAULT PULL_REQUEST_CREATE
declare -x STANDARD_CONFIG STANDARD_NAME STANDARD_URL STANDARD_CREATE

declare -x BIN_DIR SHARE_DIR SRC_DIR CFG_DIR TMPL_DIR TMP_DIR
declare -x CFG_FILE CFG_BASE CFG_TYPES CFG_DEFAULT CFG_BASE_DEFAULT CFG_TYPES_DEFAULT
declare -x TMP_CFG_FILE TMP_CFG_BASE ENV_FILE
declare -x LOG_FILE TMPL_LOG TMPL_RELEASE TMPL_PULL

declare -x FIRST_RELEASE=false
declare -x RELEASE_TAG

BIN_DIR="/usr/local/bin"
SHARE_DIR="/usr/local/share"
SRC_DIR="$BIN_DIR/src"
CFG_DIR="$SHARE_DIR/cfg"
TMPL_DIR="$CFG_DIR/tmpl"

TMP_DIR="$(mktemp -d)"

SEARCH_DIRS=("$GITHUB_WORKSPACE/.github" "$GITHUB_WORKSPACE/.github/release")

CFG_DEFAULT="$CFG_DIR/relman.yml"
CFG_BASE_DEFAULT="$CFG_DIR/relman.base.yml"
CFG_TYPES_DEFAULT="$CFG_DIR/types.conventional.yml"
CHANGELOG_TEMPLATE_DEFAULT="$TMPL_DIR/changelog.md"
RELEASE_TEMPLATE_DEFAULT="$TMPL_DIR/release.md"
PULL_REQUEST_TEMPLATE_DEFAULT="$TMPL_DIR/pull_request.md"

HEADERS=("-H \"Accept: application/vnd.github+json\"" "-H \"Authorization: Bearer ${GITHUB_TOKEN}\"" "-H \"X-GitHub-Api-Version: 2022-11-28\"")
