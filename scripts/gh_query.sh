#!/usr/bin/env sh

repo_owner=${1:-ardiustech}
repo_name=${2:-mithrin}
# Use GitHub CLI authentication or environment variable
# export GITHUB_TOKEN in your shell environment

curl -s -H "Authorization: bearer $GITHUB_TOKEN" -d '
{
    "query": "query {repository(owner: \"'$repo_owner'\", name: \"'$repo_name'\") {pullRequests(states: OPEN, first: 100) {nodes {title comments {totalCount}}}}}"
}
' https://api.github.com/graphql
