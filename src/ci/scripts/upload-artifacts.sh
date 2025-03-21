#!/bin/bash
# Upload all the artifacts to our S3 bucket. All the files inside ${upload_dir}
# will be uploaded to the deploy bucket and eventually signed and released in
# static.rust-lang.org.

set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "$0")" && pwd)/../shared.sh"

upload_dir="$(mktemp -d)"

build_dir=build
if isLinux; then
    build_dir=obj/build
fi

# Release tarballs produced by a dist builder.
if [[ "${DEPLOY-0}" -eq "1" ]] || [[ "${DEPLOY_ALT-0}" -eq "1" ]]; then
    dist_dir="${build_dir}/dist"
    rm -rf "${dist_dir}/doc"
    mv "${dist_dir}"/* "${upload_dir}"
fi

# CPU usage statistics.
cp build/cpu-usage.csv "${upload_dir}/cpu-${CI_JOB_NAME}.csv"

# Build metrics generated by x.py.
cp "${build_dir}/metrics.json" "${upload_dir}/metrics-${CI_JOB_NAME}.json"

# Toolstate data.
if [[ -n "${DEPLOY_TOOLSTATES_JSON+x}" ]]; then
    cp /tmp/toolstate/toolstates.json "${upload_dir}/${DEPLOY_TOOLSTATES_JSON}"
fi

echo "Files that will be uploaded:"
ls -lah "${upload_dir}"
echo

deploy_dir="rustc-builds"
if [[ "${DEPLOY_ALT-0}" -eq "1" ]]; then
    deploy_dir="rustc-builds-alt"
fi
deploy_url="s3://${DEPLOY_BUCKET}/${deploy_dir}/$(ciCommit)"

retry aws s3 cp --storage-class INTELLIGENT_TIERING \
    --no-progress --recursive --acl public-read "${upload_dir}" "${deploy_url}"

access_url="https://ci-artifacts.rust-lang.org/${deploy_dir}/$(ciCommit)"

# Output URLs to the uploaded artifacts to GitHub summary (if it is available)
# to make them easily accessible.
if [ -n "${GITHUB_STEP_SUMMARY}" ]
then
  archives=($(find "${upload_dir}" -maxdepth 1 -name "*.xz"))

  # Avoid generating an invalid "*.xz" file if there are no archives
  if [ ${#archives[@]} -gt 0 ]; then
    echo "# CI artifacts" >> "${GITHUB_STEP_SUMMARY}"

    for filename in "${upload_dir}"/*.xz; do
      filename=$(basename "${filename}")
      echo "- [${filename}](${access_url}/${filename})" >> "${GITHUB_STEP_SUMMARY}"
    done
  fi
fi
