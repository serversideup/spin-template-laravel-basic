#!/bin/env bash
set -e # Exit on error

###############################################
# Prepare enviornment
###############################################
PHP_IMAGE="serversideup/php:8.3-cli"
project_dir=${1:-"laravel"}

# Make sure the image is up to date before running
docker pull $PHP_IMAGE

###############################################
# Functions
###############################################

# Default function to run for new projects
new(){
  docker run --rm -w /var/www/html -v "$(pwd):/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e "SHOW_WELCOME_MESSAGE=false" $PHP_IMAGE composer --no-cache create-project laravel/laravel "$project_dir"

  # Initialize new projects too
  init
}

# Required function name "init", used in "spin init" command
init(){
  docker run --rm -v "$project_dir:/var/www/html" -e "SHOW_WELCOME_MESSAGE=false" $PHP_IMAGE composer --working-dir=/var/www/html/ require serversideup/spin --dev
}

###############################################
# Main script logic (where the script starts)
###############################################

# Default to 'new' if no argument is provided
func=${1:-new}

# Check our function exists
if declare -f "$func" > /dev/null; then
  "$func" "${@:2}"  # Call the function with remaining arguments
else
  echo "{$BOLD}{$RED}Error: '$func' is not a valid command in $0" >&2
  exit 1
fi