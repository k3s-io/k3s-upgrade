#!/bin/sh -x

# shellcheck disable=SC1091
. ./upgrade.sh

compare_versions_test() {
    failed_cases=""
    while [ $# -ge 3 ]; do
        version1="$1"
        version2="$2"
        expected_result="$3"

        compare_versions "$version1" "$version2"
        result=$?
        if [ "$result" -ne "$expected_result" ]; then
            failed_cases="${failed_cases}compare_versions_test test case failed: ${version1}, ${version2}"
        fi

        # Shift the positional parameters to move to the next test case
        shift 3
    done

    if [ -n "$failed_cases" ]; then
        echo "$failed_cases"
        exit 1
    fi

    echo "All compare_versions_test test cases passed."
}

# Function to compare semantic versions
# Returns 0 if version1 <= version2, 1 otherwise
compare_versions_test \
    "1.0.0" "1.0.0" "0" \
    "1.0.0" "1.5.0" "0" \
    "1.2.3" "1.0.0" "1" \
    "1.0.0" "1.2.3" "0" \
    "1.1.0" "1.0.10" "1" \
    "2.0.0" "2.0.0-rc1" "1"

build_date_tests() {
    # Test cases in the format: build_date1, build_date2, expected_result
    # Example: "2023-06-23T14:58:45Z" "2023-06-20T12:30:15Z" 1 (means build_date1 is more recent)
    while [ $# -ge 3 ]; do
        build_date1="$1"
        build_date2="$2"
        expected_result="$3"

        compare_build_dates "$build_date1" "$build_date2"
        result=$?
        if [ "$result" -ne "$expected_result" ]; then
            echo "Build date test case failed: $build_date1, $build_date2"
            exit 1
        fi

        # Shift the positional parameters to move to the next set of test cases
        shift 3
    done
   echo "All build_date_tests test cases passed."
}

# Function to compare build dates
# Returns 0 if build_date1 <= build_date2, 1 otherwise
build_date_tests \
    "2023-06-23T14:58:45Z" "2023-06-23T14:58:45Z" 0 \
    "2023-06-20T12:30:15Z" "2023-06-23T14:58:45Z" 0 \
    "2023-06-23T14:58:45Z" "2023-06-20T12:30:15Z" 1 \
    "2023-07-01T08:30:00Z" "2023-07-30T20:00:00Z" 0 \
    "2023-01-01T00:00:00Z" "2022-12-31T23:59:59Z" 1 \
    "2023-06-01T00:00:00Z" "2023-05-31T23:59:59Z" 1 \
    "2023-06-15T12:00:00Z" "2023-06-15T11:59:59Z" 1

