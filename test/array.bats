#!/usr/bin/env bash

load 'libs/helpers'
commonSetup

setup() {
	declare -agx ARRAY=("alpha" "bravo" "charlie")
	declare -Agx ASSOC
	ASSOC['al']="pha"
	ASSOC['br']="avo"
	ASSOC['ch']="arlie"
}

@test "arr::getIndex returns correct element index" {
	# shellcheck source="../../src/array.sh"
	source "./src/array.sh"
	run arr::getIndex bravo "${ARRAY[@]}"
	assert_success
	assert_output "1"
}

@test "arr::hasKey returns correct status" {
	# shellcheck source="../../src/array.sh"
	source "./src/array.sh"
	run arr::hasKey ASSOC "al"
	assert_success
}

@test "arr::hasVal returns correct status" {
	# shellcheck source="../../src/array.sh"
	source "./src/array.sh"
	run arr::hasVal charlie "${ARRAY[@]}"
	assert_success
}
