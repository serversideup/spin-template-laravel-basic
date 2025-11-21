#!/bin/env bash
set -e # Exit on error

###############################################
# Prepare environment
###############################################
# Capture input arguments
laravel_framework_args=("$@")

# Default PHP Docker Image
SPIN_PHP_VERSION="${SPIN_PHP_VERSION:-8.5}"
SPIN_PHP_DOCKER_INSTALLER_IMAGE="${SPIN_PHP_DOCKER_INSTALLER_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-cli}"
SPIN_PHP_DOCKER_BASE_IMAGE="${SPIN_PHP_DOCKER_BASE_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-fpm-nginx-alpine}"
SPIN_PHP_DOCKER_IMAGE_PREFIX="${SPIN_PHP_DOCKER_IMAGE_PREFIX:-}"

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

SERVER_CONTACT=""

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
    local php_versions=("8.5" "8.4" "8.3" "8.2" "8.1" "8.0" "7.4")
    local php_choice

    # If SPIN_ACTION is "new", filter out versions below 8.2
    if [ "$SPIN_ACTION" == "new" ]; then
        php_versions=("8.5" "8.4" "8.3" "8.2")
    fi
    
    # Filter PHP versions based on variation requirements
    if [[ "$SPIN_PHP_VARIATION" == "frankenphp" ]]; then
        php_versions=("8.5" "8.4" "8.3")
    fi

    while true; do
        clear
        show_header
        echo "${BOLD}${YELLOW}👉 What PHP version would you like to use?${RESET}"
        
        # Show variation-specific note if applicable
        if [[ "$SPIN_PHP_VARIATION" == "frankenphp" ]]; then
            echo "${DIM}Note: FrankenPHP requires PHP 8.3 or higher${RESET}"
        fi
        echo ""
        
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
            [1-${#php_versions[@]}]) SPIN_PHP_VERSION="${php_versions[$((php_choice-1))]}" ;;
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
    sleep 1
}

prompt_php_variation() {
    local variations=("fpm-nginx" "frankenphp" "fpm-apache")
    local variation_descriptions=(
        "PHP-FPM + NGINX (Traditional, widely adopted)"
        "FrankenPHP (Laravel Octane, worker mode, HTTP/2 & HTTP/3)"
        "PHP-FPM + Apache (Ideal for WordPress, .htaccess support)"
    )
    local variation_choice

    # Set default if not already set
    [[ -z "$SPIN_PHP_VARIATION" ]] && SPIN_PHP_VARIATION="fpm-nginx"

    while true; do
        clear
        show_header
        echo "${BOLD}${YELLOW}👉 What server variation would you like to use?${RESET}"
        echo ""
        
        for i in "${!variations[@]}"; do
            local variation="${variations[$i]}"
            local description="${variation_descriptions[$i]}"
            local display="$((i+1))) $variation"
            [[ "$variation" == "${variations[0]}" ]] && display+=" ${DIM}${RESET}"
            
            if [[ "$SPIN_PHP_VARIATION" == "$variation" ]]; then
                echo -e "${BOLD}${BLUE}$display${RESET}"
                echo -e "   ${DIM}$description${RESET}"
            else
                echo -e "$display"
                echo -e "   ${DIM}$description${RESET}"
            fi
            echo ""
        done
        
        echo "Press a number to select. Press ${BOLD}${BLUE}ENTER${RESET} to continue."
        
        read -n 1 variation_choice
        case $variation_choice in
            [1-${#variations[@]}]) SPIN_PHP_VARIATION="${variations[$((variation_choice-1))]}" ;;
            "") 
                [[ -n "$SPIN_PHP_VARIATION" ]] && break
                echo "${BOLD}${RED}Please select a variation.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
            *) 
                echo "${BOLD}${RED}Invalid choice. Please try again.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
        esac
    done

    echo ""
    echo "${BOLD}${GREEN}✅ $SPIN_PHP_VARIATION selected.${RESET}"
    export SPIN_PHP_VARIATION
    sleep 1
}

prompt_php_os() {
    local os_options=("debian" "alpine")
    local os_descriptions=(
        "Debian (Stable, widely compatible, larger image)"
        "Alpine (Lightweight, smaller image, minimal footprint)"
    )
    local os_choice

    # Set default if not already set
    [[ -z "$SPIN_PHP_OS" ]] && SPIN_PHP_OS="debian"

    while true; do
        clear
        show_header
        echo "${BOLD}${YELLOW}👉 What operating system would you like to use?${RESET}"
        echo ""
        
        for i in "${!os_options[@]}"; do
            local os="${os_options[$i]}"
            local description="${os_descriptions[$i]}"
            local display="$((i+1))) $os"
            [[ "$os" == "${os_options[0]}" ]] && display+=" ${DIM}${RESET}"
            
            if [[ "$SPIN_PHP_OS" == "$os" ]]; then
                echo -e "${BOLD}${BLUE}$display${RESET}"
                echo -e "   ${DIM}$description${RESET}"
            else
                echo -e "$display"
                echo -e "   ${DIM}$description${RESET}"
            fi
            echo ""
        done
        
        echo "Press a number to select. Press ${BOLD}${BLUE}ENTER${RESET} to continue."
        
        read -n 1 os_choice
        case $os_choice in
            [1-${#os_options[@]}]) SPIN_PHP_OS="${os_options[$((os_choice-1))]}" ;;
            "") 
                [[ -n "$SPIN_PHP_OS" ]] && break
                echo "${BOLD}${RED}Please select an operating system.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
            *) 
                echo "${BOLD}${RED}Invalid choice. Please try again.${RESET}"
                read -n 1 -r -p "Press any key to continue..."
                ;;
        esac
    done

    echo ""
    echo "${BOLD}${GREEN}✅ $SPIN_PHP_OS selected.${RESET}"
    export SPIN_PHP_OS
    sleep 1
}

show_header() {
        printf '%s      ___     %s      ___   %s            %s      ___     %s\n'      $RAINBOW $RESET
        printf '%s     /  /\    %s     /  /\  %s    ___     %s     /__/\    %s\n'      $RAINBOW $RESET
        printf '%s    /  /:/_   %s    /  /::\ %s   /  /\    %s     \  \:\   %s\n'      $RAINBOW $RESET
        printf '%s   /  /:/ /\  %s   /  /:/\:\%s  /  /:/    %s      \  \:\  %s\n'      $RAINBOW $RESET
        printf '%s  /  /:/ /::\ %s  /  /:/~/:/%s /__/::\    %s  _____\__\:\ %s\n'      $RAINBOW $RESET
        printf '%s /__/:/ /:/\:\%s /__/:/ /:/ %s \__\/\:\__ %s /__/::::::::\%s\n'      $RAINBOW $RESET
        printf '%s \  \:\/:/~/:/%s \  \:\/:/  %s    \  \:\/\%s \  \:\~~\~~\/%s\n'      $RAINBOW $RESET
        printf '%s  \  \::/ /:/ %s  \  \::/   %s     \__\::/%s  \  \:\  ~~~ %s\n'      $RAINBOW $RESET
        printf '%s   \__\/ /:/  %s   \  \:\   %s     /__/:/ %s   \  \:\     %s\n'      $RAINBOW $RESET
        printf '%s     /__/:/   %s    \  \:\  %s     \__\/  %s    \  \:\    %s\n'      $RAINBOW $RESET
        printf '%s     \__\/    %s     \__\/  %s            %s     \__\/    %s\n'      $RAINBOW $RESET
        printf '\n'
        printf "%s\n" "${BOLD}🚀 Let's get Laravel launched!"
        printf '%s\n' $RESET
}

assemble_php_docker_image() {
    
    # For debian, we don't include it in the tag (it's the default)
    if [[ "$SPIN_PHP_OS" == "debian" ]]; then
        export SPIN_PHP_DOCKER_INSTALLER_IMAGE="serversideup/php:${SPIN_PHP_DOCKER_IMAGE_PREFIX}${SPIN_PHP_VERSION}-cli"
        export SPIN_PHP_DOCKER_BASE_IMAGE="serversideup/php:${SPIN_PHP_DOCKER_IMAGE_PREFIX}${SPIN_PHP_VERSION}-${SPIN_PHP_VARIATION}"
    else
        export SPIN_PHP_DOCKER_INSTALLER_IMAGE="serversideup/php:${SPIN_PHP_DOCKER_IMAGE_PREFIX}${SPIN_PHP_VERSION}-cli-${SPIN_PHP_OS}"
        export SPIN_PHP_DOCKER_BASE_IMAGE="serversideup/php:${SPIN_PHP_DOCKER_IMAGE_PREFIX}${SPIN_PHP_VERSION}-${SPIN_PHP_VARIATION}-${SPIN_PHP_OS}"
    fi
    
    echo ""
    echo "${BOLD}${BLUE}📦 Docker Base Image:${RESET} $SPIN_PHP_DOCKER_BASE_IMAGE"
    echo ""
    sleep 1
}

###############################################
# Main Spin Action Functions
###############################################

# Default function to run for new projects
new(){
  docker pull "$SPIN_PHP_DOCKER_INSTALLER_IMAGE"

  # Use the current working directory for our install command
  docker run --rm \
    -v "$(pwd):/var/www/html" \
    --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
    -e COMPOSER_CACHE_DIR=/dev/null \
    -e "SHOW_WELCOME_MESSAGE=false" \
    "$SPIN_PHP_DOCKER_INSTALLER_IMAGE" \
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
  fi
}

###############################################
# Main: Where we call the functions
###############################################

prompt_php_variation
prompt_php_version
prompt_php_os
assemble_php_docker_image

SERVER_CONTACT=$(prompt_and_update_file \
    --title "🤖 Server Contact" \
    --details "Set an email contact who should be notified for Let's Encrypt SSL renewals and other system alerts." \
    --prompt "Please enter your email" \
    --output-only \
    --validate "email")

export SERVER_CONTACT

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