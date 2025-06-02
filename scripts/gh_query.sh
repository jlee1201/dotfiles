#!/usr/bin/env sh

# Load environment variables from .env file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
if [ -f "$SCRIPT_DIR/.env" ]; then
  . "$SCRIPT_DIR/.env"
fi

repo_owner=${1:-ardiustech}
repo_name=${2:-mithrin}

# Check if token exists
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set. Please add it to .env file or export it manually."
  exit 1
fi

curl -s -H "Authorization: bearer $GITHUB_TOKEN" -d '
{
    "query": "query {repository(owner: \"'$repo_owner'\", name: \"'$repo_name'\") {pullRequests(states: OPEN, first: 100) {nodes {title comments {totalCount}}}}}"
}
' https://api.github.com/graphql
