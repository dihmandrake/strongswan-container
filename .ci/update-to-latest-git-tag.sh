#!/bin/sh

versionRegex="^[0-9]+\.[0-9]+\.[0-9]+$"


git fetch
git fetch --tags
currentTag=$(git tag --points-at HEAD)
echo "Currently at tag: $currentTag"
latestTag=$(git tag -l --sort=v:refname | tr ' ' '\n' | grep -P "${versionRegex}" | tail -n 1)
echo "Found latest tag in repo: $latestTag"


if [ "$latestTag" != "$currentTag" ]; then
    echo "Git checking out to: $latestTag"
    git checkout "$latestTag"
else
    echo "No new git tag found in repo."
fi
