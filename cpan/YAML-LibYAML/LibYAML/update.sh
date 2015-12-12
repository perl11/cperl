#!/bin/bash

libyaml=../../libyaml
source="$libyaml/src"
include="$libyaml/include"
need_branch=perl-yaml-xs

if [ ! -d "$source" ]; then
  echo "'$source' does not exist"
  exit 1
fi

libyaml_branch="$(
  cd "$libyaml"
  git rev-parse --abbrev-ref HEAD
)"

if [ "$libyaml_branch" != "$need_branch" ]; then
  echo "libyaml must be set to branch '$need_branch'"
  exit 1
fi

diff="$(
  diff -q $source . |
  grep -v '^Only'
  diff -q $include . |
  grep -v '^Only'
)"

if [ -n "$diff" ]; then
  echo "*** Updating from libyaml repository ***"
  diff -q "$source" . | grep -v '^Only'
  cp "$source"/*.{c,h} .
  diff -q "$include" . | grep -v '^Only'
  cp "$include"/*.h .
fi
