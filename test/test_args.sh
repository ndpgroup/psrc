#!/bin/sh

test_args() {
  local i
  ((i=0))
  printf '$* = %s\n' "$*"
  echo '$@ =' "$@"
  while [ -n "$1" ]; do
    ((i=i+1))
    printf '$%d = %s\n' $i "$1"
    shift
  done
}
