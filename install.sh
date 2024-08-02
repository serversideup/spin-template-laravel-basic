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
# Configure "SPIN_PROJECT_DIRECTORY" variable
# This variable MUST be the ABSOLUTE path
###############################################

# Determine the project directory based on the SPIN_ACTION
if [ "$SPIN_ACTION" == "new" ]; then
  # Use the first framework argument or default to "laravel"
  laravel_project_directory=${framework_args[0]:-laravel}
  # Set the absolute path to the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)/$laravel_project_directory"

elif [ "$SPIN_ACTION" == "init" ]; then
  # Use the current working directory for the project directory
  SPIN_PROJECT_DIRECTORY="$(pwd)"
fi

# Export the project directory
export SPIN_PROJECT_DIRECTORY

###############################################
# Functions
###############################################

ensure_line_in_file() {
    local mode="update"
    local files=()
    local search=""
    local replace=""
    local after=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --update)
                mode="update"
                shift
                ;;
            --after)
                mode="after"
                shift
                ;;
            --file)
                shift
                files+=("$1")
                shift
                ;;
            *)
                if [[ -z $search ]]; then
                    search="$1"
                elif [[ -z $replace ]]; then
                    replace="$1"
                elif [[ $mode == "after" && -z $after ]]; then
                    after="$replace"
                    replace="$1"
                else
                    echo "Too many arguments"
                    return 1
                fi
                shift
                ;;
        esac
    done

    # Check if at least one file is specified
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files specified. Use --file argument to specify files."
        return 1
    fi

    # Process each file
    for file in "${files[@]}"; do
        # Check if file exists
        if [ ! -f "$file" ]; then
            echo "File not found: $file"
            continue
        fi

        # Handle different modes
        if [[ $mode == "update" ]]; then
            if grep -q "$search" "$file"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "s|.*$search.*|$replace|" "$file"
                else
                    # Linux and others
                    sed -i "s|.*$search.*|$replace|" "$file"
                fi
            else
                echo "$replace" >> "$file"
            fi
        elif [[ $mode == "after" ]]; then
            if grep -q "$search" "$file"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "/^$search/a\\
$replace
" "$file"
                else
                    # Linux and others
                    sed -i "/^$search/a $replace" "$file"
                fi
            else
                echo "Search string not found in $file: $search"
            fi
        fi
    done
}

# Default function to run for new projects
new(){
  # Use the current working directory for our install command
  docker run --rm -v "$(pwd):/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $docker_image composer --no-cache create-project laravel/laravel "${framework_args[@]}"

  # We want to initialize the project, so pass the "--force" flag to the init function
  init --force
}

# Required function name "init", used in "spin init" command
init(){
  local init_sqlite=false
  local sqlite_detected=false

  # Check if the "--force" flag was passed
  if [ "$1" == "--force" ]; then
    init_sqlite=true
  fi

  # Install the spin package
  docker run --rm -v "$SPIN_PROJECT_DIRECTORY:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $docker_image composer --verbose --working-dir=/var/www/html/ require serversideup/spin:dev-75-spin-deploy-allow-deployments-without-cicd --dev

  # Determine SQLite is being used
  if grep -q 'DB_CONNECTION=sqlite' "$SPIN_PROJECT_DIRECTORY/.env"; then
    sqlite_detected=true
  fi

  if [[ "$init_sqlite" == false && "$sqlite_detected" == true ]]; then
    echo "${BOLD}${YELLOW}[spin-template-laravel] 👉 We detected SQLite being used on this project.${RESET}"
    echo "${BOLD}${YELLOW}[spin-template-laravel] 👉 We need to update the .env file to use the correct path.${RESET}"
    echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 This means you may need to manually move your data to the path for the database.${RESET}"
    echo ""
    read -n 1 -r -p "${BOLD}${YELLOW}[spin-template-laravel] 🤔 Would you like us to automatically configure SQLite for you? [Y/n]${RESET} " response

    if [[ $response =~ ^([nN][oO]|[nN])$ ]]; then
      echo ""
      echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 You will need to manually move your SQLite database to the correct path.${RESET}"
      echo "${BOLD}${YELLOW}[spin-template-laravel] 🚨 The path is: ${RESET}/.infrastructure/volume_data/sqlite/database.sqlite"
      echo ""
    else
      init_sqlite=true
    fi
  fi

  if [ "$init_sqlite" == true ]; then
    # Create the SQLite database folder
    mkdir -p "$SPIN_PROJECT_DIRECTORY/.infrastructure/volume_data/sqlite"

    ensure_line_in_file --file "$SPIN_PROJECT_DIRECTORY/.env" --file "$SPIN_PROJECT_DIRECTORY/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
    ensure_line_in_file --file "$SPIN_PROJECT_DIRECTORY/.env" --file "$SPIN_PROJECT_DIRECTORY/.env.example" --after "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

    # Run migrations
    docker run --rm -v "$SPIN_PROJECT_DIRECTORY:/var/www/html" --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e COMPOSER_CACHE_DIR=/dev/null -e "SHOW_WELCOME_MESSAGE=false" $docker_image php /var/www/html/artisan migrate --force

  fi
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