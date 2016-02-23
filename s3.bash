#!/usr/bin/env bash

declare help="
Script for uploading a given directory (optionally targzipped) to S3.

Usage:
  s3.bash [-k <key>] [-s <secret>] -d <path> [-b <bucket>] [-C | -X]
  s3.bash --version
  s3.bash -h | --help

Options:
  -k                S3 key.
  -s                S3 secret.
  -d                Directory to be uploaded.
  -C                Compress as .tar.gz.
  -X                Compress as .tar.xz.
  -b                S3 bucket's name.
  --version         Show versions.
  -h | --help       Show this screen.
"

declare version="
Version: 1.0.0.
Licensed under the MIT terms.
"

declare file
declare -a list
declare directory
declare bucket="${BUCKET:-your-bucket}"
declare contentType="application/x-compressed-tar"
declare dateValue
dateValue=$(date +"%a, %d %b %Y %T %z")
declare s3Key="${S3_KEY:-none}"
declare s3Secret="${S3_SECRET:-none}"
declare COMPRESS="false"
declare COMPRESS_ALG

gen_sig() {
  declare resource="/$bucket/$file"
  declare stringToSign="PUT\n\n$contentType\n$dateValue\n$resource"
  declare sig
  sig=$(echo -en "$stringToSign" | openssl sha1 -hmac "$s3Secret" -binary | base64)
}

upload() {
  curl -X PUT -T "$file" \
    -H "Host: $bucket.s3.amazonaws.com" \
    -H "Date: $dateValue" \
    -H "Content-Type: ${contentType}" \
    -H "Authorization: AWS $s3Key:$sig" \
    https://"$bucket".s3.amazonaws.com/"$file"
}

determineOpts() {
  while getopts ":k:s:d:b:CX" opt "$@"; do
    case "$opt" in
      k)      s3Key="$OPTARG";;
      s)      s3Secret="$OPTARG";;
      d)      directory="$OPTARG";;
      b)      bucket="$OPTARG";;
      C)      COMPRESS="true"; COMPRESS_ALG="GZ";;
      X)      COMPRESS="true"; COMPRESS_ALG="XZ";;
      \?)     echo "Ignoring unknown option $OPTARG" >&2 ;;
      :)      echo "Option -$OPTARG needs an argument" >&2 ;;
    esac
  done
  if [ "$COMPRESS" == "true" ] && [ "$COMPRESS_ALG" == "GZ" ]; then
    file="/tmp/$(date +%s).tar.gz"
    tar -czf "$file" "$directory"
  fi
  if [ "$COMPRESS" == "true" ] && [ "$COMPRESS_ALG" == "XZ" ]; then
    file="/tmp/$(date +%s).tar.xz"
    tar -cf - "$directory" | xz -9 -c - > "$file"
  fi
  if [ "$COMPRESS" == "true" ]; then
    gen_sig
    upload
  fi

  if [ "$COMPRESS" == "false" ]; then
    files=$(find "$directory")
    for each in $files; do
      if [ -f "$each" ]; then
      file="$each"
        gen_sig
        upload
      fi
    done
  fi
}

main() {
  set -eo pipefail; [[ "$TRACE" ]] && set -x
  declare cmd="$1"
  case "$cmd" in
    -h|--help)      shift; echo "$help";;
    --version)      shift; echo "$version";;
    *)              determineOpts "$@";;
  esac
}

main "$@"
