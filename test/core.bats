#!/usr/bin/env bash
# shellcheck disable=SC2181

load 'libs/helpers'
commonSetup

@test "core::parseVersion returns populated array" {
	declare -Agx ARRAY
	source "./src/error.sh"
	source "./src/regex.sh"
	source "./src/core.sh"
	core::parseVersion "v1.1.4-alpha+6b" ARRAY
	[ "$?" -eq 0 ]
	assert_equal "${ARRAY['full']}" "v1.1.4-alpha+6b"
	assert_equal "${ARRAY['prefix']}" "v"
	assert_equal "${ARRAY['version']}" "1.1.4"
	assert_equal "${ARRAY['major']}" "1"
	assert_equal "${ARRAY['minor']}" "1"
	assert_equal "${ARRAY['patch']}" "4"
	assert_equal "${ARRAY['suffix']}" "alpha"
	assert_equal "${ARRAY['build']}" "6b"
	assert_equal "${ARRAY['n_version']}" "114"
}
