#!/bin/env bash
set -e # Exit on error

###############################################
# Prepare enviornment
###############################################
# Capture input arguments
laravel_framework_args=("$@")

# Default PHP Docker Image
SPIN_PHP_VERSION="${SPIN_PHP_VERSION:-8.3}"
SPIN_PHP_DOCKER_IMAGE="${SPIN_PHP_DOCKER_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-cli}"
export SPIN_PHP_DOCKER_IMAGE

# Set project files
declare -a spin_project_files=(
  "vendor"
  "node_modules"
  "yarn.lock"
  "composer.lock"
  "package-lock.json"
  ".infrastructure"
  "docker-compose*"
  "Dockerfile*"
)

###############################################
# Configure "SPIN_PROJECT_DIRECTORY" variable
# This variable MUST be the ABSOLUTE path
###############################################

# Determine the project directory based on the SPIN_ACTION
if [ "$SPIN_ACTION" == "new" ]; then
  laravel_project_directory=${laravel_framework_args[0]:-laravel}
  # Set the absolute path to the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)/$laravel_project_directory"

elif [ "$SPIN_ACTION" == "init" ]; then
  # Use the current working directory for the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)"
fi

# Export the project directory
export SPIN_PROJECT_DIRECTORY

###############################################
# Helper Functions
###############################################

delete_matching_pattern() {
  local pattern="$1"
  
  # Use shell globbing for pattern matching
  shopt -s nullglob
  local files=("$SPIN_PROJECT_DIRECTORY"/$pattern)
  shopt -u nullglob

  # If files are found, delete them
  if [ ${#files[@]} -gt 0 ]; then
    rm -rf "${files[@]}"
  fi
}

display_destructive_action_warning(){
    clear
    echo "${BOLD}${RED}⚠️  WARNING ⚠️${RESET}"
    echo "${YELLOW}Please read the following carefully:${RESET}"
    echo "• Potential data loss may occur during this process."
    echo "• Ensure you are running this on a non-production branch."
    echo "• Make sure you have backups of your files and database."
    echo "• We will attempt to update your vite.config.js file."
    echo "• We will be deleting and reinstalling dependencies based on your composer and node settings."
    echo "• We will attempt to automatically update your ENV files."
    echo ""
    read -p "${BOLD}${YELLOW}Do you want to proceed? (y/N): ${RESET}" confirm

    case "$confirm" in
      [yY])
        # Silence is golden
        ;;
      *)
        echo "${RED}Initialization cancelled. Exiting...${RESET}"
        exit 1
        ;;
    esac
}

project_files_exist() {
  local -a files=("$@")
  for item in "${files[@]}"; do
    if compgen -G "$SPIN_PROJECT_DIRECTORY/$item" > /dev/null; then
      return 0  # True: At least one matching file exists
    fi
  done
  return 1  # False: No matching files found
}

prompt_php_version() {
    local php_versions=("8.3" "8.2" "8.1" "8.0" "7.4")
    local php_choice

    while true; do
        clear
        echo "${BOLD}${YELLOW}👉 What PHP version would you like to use?${RESET}"
        
        for i in "${!php_versions[@]}"; do
            local version="${php_versions[$i]}"
            local display="$((i+1))) PHP $version"
            [[ "$version" == "${php_versions[0]}" ]] && display+=" (Latest)"
            [[ "$SPIN_PHP_VERSION" == "$version" ]] && display="${BOLD}${BLUE}$display${RESET}" || display="$display"
            echo -e "$display"
        done
        
        echo ""
        echo "Press a number to select. Press ${BOLD}${BLUE}ENTER${RESET} to continue."
        
        read -n 1 php_choice
        case $php_choice in
            [1-5]) SPIN_PHP_VERSION="${php_versions[$((php_choice-1))]}" ;;
            "") 
                [[ -n "$SPIN_PHP_VERSION" ]] && break
                echo "${BOLD}${RED}Please select a PHP version.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
            *) 
                echo "${BOLD}${RED}Invalid choice. Please try again.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
        esac
    done

    echo ""
    echo "${BOLD}${GREEN}✅ PHP $SPIN_PHP_VERSION selected.${RESET}"
    

    export SPIN_PHP_VERSION
    export SPIN_PHP_DOCKER_IMAGE="serversideup/php:${SPIN_PHP_VERSION}-cli"
    
    sleep 1
}

###############################################
# Main Spin Action Functions
###############################################

# Default function to run for new projects
new(){
  docker pull "$SPIN_PHP_DOCKER_IMAGE"

  # Use the current working directory for our install command
  docker run --rm \
    -v "$(pwd):/var/www/html" \
    --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
    -e COMPOSER_CACHE_DIR=/dev/null \
    -e "SHOW_WELCOME_MESSAGE=false" \
    "$SPIN_PHP_DOCKER_IMAGE" \
    composer --no-cache create-project laravel/laravel "${laravel_framework_args[@]}"

  init --force
}

# Required function name "init", used in "spin init" command
init(){
  local force_flag=""

  # Check if --force flag is set
  for arg in "$@"; do
    if [ "$arg" == "--force" ]; then
      force_flag="true"
      break
    fi
  done

  if [ "$SPIN_ACTION" != "new" ]; then
    if project_files_exist "${spin_project_files[@]}" && [ "$force_flag" != "true" ]; then
      display_destructive_action_warning
    fi

    for item in "${spin_project_files[@]}"; do
      delete_matching_pattern "$item"
    done

    prompt_php_version

    if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
      echo "Re-installing composer dependencies..."

      docker pull "$SPIN_PHP_DOCKER_IMAGE"

      # Install Spin
      docker run --rm \
        -v "$(pwd):/var/www/html" \
        --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
        -e COMPOSER_CACHE_DIR=/dev/null \
        -e "SHOW_WELCOME_MESSAGE=false" \
        "$SPIN_PHP_DOCKER_IMAGE" \
        composer require serversideup/spin --dev

      # Use the current working directory for our install command
      docker run --rm \
        -v "$(pwd):/var/www/html" \
        --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
        -e COMPOSER_CACHE_DIR=/dev/null \
        -e "SHOW_WELCOME_MESSAGE=false" \
        "$SPIN_PHP_DOCKER_IMAGE" \
        composer install
    fi

  fi
}

###############################################
# Main: Where we call the functions
###############################################

# When spin calls this script, it already sets a variable
# called $SPIN_ACTION (that will have a value of "new" or "init")

# Check to see if SPIN_ACTION function exists
if type "$SPIN_ACTION" &>/dev/null; then
  # Call the function
  $SPIN_ACTION
else
  # If the function does not exist, throw an error
  echo "The function '$SPIN_ACTION' does not exist."
  exit 1
fi