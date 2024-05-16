#!/bin/env bash
set -e # Exit on error

###############################################
# Prepare enviornment
###############################################

# Make sure the image is up to date before running
docker_image="serversideup/php:8.3-cli"
docker pull $docker_image

# Save anything passed to the script as an array
framework_args=("$@")

###############################################
# Configure "SPIN_PROJECT_DIRECTORY" for new installs
###############################################

# Spin needs to know what the project directory is
# for new installations. You MUST export this variable
# to Spin so it can complete the installation correctly.

if [ "$SPIN_ACTION" == "new" ]; then

  # Check if any framework arguments were passed
  if [ ${#framework_args[@]} -eq 0 ]; then
    # Set default directory to Laravel
    SPIN_PROJECT_DIRECTORY="laravel"
  else
    # Grab the first argument as the project directory (this is what Laravel does)
    SPIN_PROJECT_DIRECTORY="${framework_args[0]}"
  fi

  # Export this variable back to Spin
  export SPIN_PROJECT_DIRECTORY

fi

###############################################
# Functions
###############################################

# Default function to run for new projects
new(){
  docker run --rm -v "$(pwd):/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $docker_image composer --no-cache create-project laravel/laravel "${framework_args[@]}"

  # Create the SQLite database folder
  mkdir -p "$(pwd)/$SPIN_PROJECT_DIRECTORY/.infrastructure/volumes/sqlite"

  # Create the SQLite database file
  touch "$(pwd)/$SPIN_PROJECT_DIRECTORY/.infrastructure/volumes/sqlite/database.sqlite"

  # Ensure the .env file has a proper path
  sed -i '/^DB_CONNECTION=sqlite$/a DB_DATABASE=/var/www/html/.infrastructure/volumes/sqlite/database.sqlite' .env

  # Initialize new projects too
  init
}

# Required function name "init", used in "spin init" command
init(){
  docker run --rm -v "$(pwd)/$SPIN_PROJECT_DIRECTORY:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $docker_image composer --verbose --working-dir=/var/www/html/ require serversideup/spin:dev-75-spin-deploy-allow-deployments-without-cicd --dev
}

###############################################
# Main: Where we call the functions
###############################################

# When spin calls this script, it already sets a variable
# called $SPIN_ACTION (that will have a value of "new" or "init)

# Check to see if SPIN_ACTION function exists
if type "$SPIN_ACTION" &>/dev/null; then
  # Call the function
  $SPIN_ACTION
else
  # If the function does not exist, throw an error
  echo "The function '$SPIN_ACTION' does not exist."
  exit 1
fi