#!/bin/sh

versionRegex="^[0-9]+\.[0-9]+\.[0-9]+$"


git fetch
latestTag=$(git tag -l --sort=v:refname | tr ' ' '\n' | grep -P "${versionRegex}" | tail -n 1)
currentTag=$(git tag --points-at HEAD)


if [ "$latestTag" != "$currentTag" ]; then
    echo "Git checking out to: $latestTag"
    git checkout "$latestTag"
else
    echo "No new git tag found in repo."
fi
