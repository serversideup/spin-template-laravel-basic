#!/bin/bash

# Capture Spin Variables
SPIN_ACTION=${SPIN_ACTION:-"install"}
SPIN_PHP_VERSION="${SPIN_PHP_VERSION:-8.3}"
SPIN_PHP_DOCKER_IMAGE="${SPIN_PHP_DOCKER_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-cli}"
javascript_package_manager="yarn"

# Set project variables
project_dir=${SPIN_PROJECT_DIRECTORY:-"$(pwd)/template"}

###############################################
# Functions
###############################################
add_php_extensions() {
    echo "${BLUE}Adding custom PHP extensions...${RESET}"
    local dockerfile="$project_dir/Dockerfile"
    
    # Check if Dockerfile exists
    if [ ! -f "$dockerfile" ]; then
        echo "Error: $dockerfile not found."
        return 1
    fi
    
    # Uncomment the USER root line
    line_in_file --action replace --file "$dockerfile" "# USER root" "USER root"
    
    # Add RUN command to install extensions
    local extensions_string="${php_extensions[*]}"
    line_in_file --action replace --file "$dockerfile" "# RUN install-php-extensions" "RUN install-php-extensions $extensions_string"
    
    echo "Custom PHP extensions added."
}

display_php_extensions_menu() {
    clear
    echo "${BOLD}${YELLOW}What PHP extensions would you like to include?${RESET}"
    echo ""
    echo "${BLUE}Default extensions:${RESET}"
    echo "ctype, curl, dom, fileinfo, filter, hash, mbstring, mysqli,"
    echo "opcache, openssl, pcntl, pcre, pdo_mysql, pdo_pgsql, redis,"
    echo "session, tokenizer, xml, zip"
    echo ""
    echo "${BLUE}Learn more here:${RESET}"
    echo "https://serversideup.net/docker-php/default-config"
    echo ""
    echo "Enter additional extensions as a comma-separated list (no spaces).${RESET}"
    echo "Example: gd,imagick,intl"
    echo ""
    echo "${BOLD}${YELLOW}Enter comma separated extensions below or press ${BOLD}${BLUE}ENTER${RESET} ${BOLD}${YELLOW}to use default extensions.${RESET}"
    read -r extensions_input

    # Remove spaces and split into array
    IFS=',' read -r -a php_extensions <<< "${extensions_input// /}"

    # Print selected extensions for confirmation
    if [ ${#php_extensions[@]} -gt 0 ]; then
        clear
        echo "${BOLD}${YELLOW}These extensions names must be supported in the PHP version you selected.${RESET}"
        echo "Learn more here: https://serversideup.net/docker-php/available-extensions"
        echo ""
        echo "${BLUE}PHP Version:${RESET} $SPIN_PHP_VERSION"
        echo "${BLUE}Extensions:${RESET}"
        for extension in "${php_extensions[@]}"; do
            echo "- $extension"
        done
        echo ""
        read -n 1 -s -r -p "${BOLD}${YELLOW}Press ${BLUE}any key${RESET} ${BOLD}${YELLOW}to continue...${RESET}"
        echo
    else
        echo "Using default PHP extensions."
    fi
}

install_node_dependencies() {
    if [[ ! -d "$project_dir" ]]; then
        echo "Error: Project directory '$project_dir' does not exist." >&2
        return 1
    fi

    if ! cd "$project_dir"; then
        echo "Error: Failed to change to project directory '$project_dir'." >&2
        return 1
    fi

    if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
        echo "${BOLD}${YELLOW}🔄 Installing Node dependencies with ${javascript_package_manager}...${RESET}"
        if ! $COMPOSE_CMD run --no-deps --rm --remove-orphans node ${javascript_package_manager} install; then
            echo "${BOLD}${RED}Error: Failed to install node dependencies.${RESET}" >&2
            return 1
        fi
        echo "Node dependencies installed successfully."
    fi
}

setup_sqlite() {
    local service_name="sqlite"
    local init_sqlite=true
    local laravel_default_sqlite_database_path="$project_dir/database/database.sqlite"
    local spin_sqllite_datbase_path="$project_dir/.infrastructure/volume_data/sqlite/database.sqlite"

    if [[ "$SPIN_ACTION" == "init" ]] && grep -q 'DB_CONNECTION=sqlite' "$SPIN_PROJECT_DIRECTORY/.env"; then
        echo "${BOLD}${YELLOW}👉 We detected SQLite being used on this project.${RESET}"
        echo "${BOLD}${YELLOW}👉 We need to update the .env file to use the correct path.${RESET}"
        echo "${BOLD}${YELLOW}🚨 This means you may need to manually move your data to the path for the database.${RESET}"
        echo ""
        read -n 1 -r -p "${BOLD}${YELLOW}🤔 Would you like us to automatically configure SQLite for you? [Y/n]${RESET} " response

        if [[ $response =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "${BOLD}${YELLOW}🚨 You will need to manually move your SQLite database to the correct path.${RESET}"
            echo "${BOLD}${YELLOW}🚨 The path is: ${RESET}${spin_sqllite_datbase_path}"
            echo ""
            init_sqlite=false
            add_user_todo_item "Move your SQLite database to \"${spin_sqllite_datbase_path}\"."
        fi
    fi

    if [ "$init_sqlite" == true ]; then
        # Create the SQLite database folder
        mkdir -p "$project_dir/.infrastructure/volume_data/sqlite"

        echo "$service_name: Updating the Laravel .env and .env.example files..."
        line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
        line_in_file --action after --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

        # Check if the default Laravel SQLite database exists and the Spin SQLite database doesn't
        if [[ -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqllite_datbase_path" ]]; then
            echo "Moving existing SQLite database to new location..."
            mv "$laravel_default_sqlite_database_path" "$spin_sqllite_datbase_path"
            echo "SQLite database moved successfully."
        elif [[ ! -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqllite_datbase_path" ]]; then
            echo "No existing SQLite database found. Running migrations to create a new one..."
            # Run the migrations to create the SQLite database
            docker run --rm \
                -v "$project_dir:/var/www/html" \
                --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
                -e COMPOSER_CACHE_DIR=/dev/null \
                -e "SHOW_WELCOME_MESSAGE=false" \
                "$SPIN_PHP_DOCKER_IMAGE" \
                php /var/www/html/artisan migrate --force
        else
            echo "SQLite database already exists in the correct location. Skipping migration."
        fi
    fi
}


###############################################
# Main
###############################################

# PHP Extensions
display_php_extensions_menu

# Set PHP Version if init
if [[ "$SPIN_ACTION" == "init" ]]; then
    line_in_file --action replace --file "$project_dir/Dockerfile" "FROM serversideup" "FROM serversideup/php:${SPIN_PHP_VERSION}-fpm-nginx-alpine as base"
fi

# Add PHP Extensions if available
if [ ${#php_extensions[@]} -gt 0 ]; then
    add_php_extensions
fi

if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
    install_node_dependencies
fi

setup_sqlite

# Configure Let's Encrypt
prompt_and_update_file \
    --title "🔐 Configure Let's Encrypt" \
    --details "Let's Encrypt requires an email address to send notifications about SSL renewals." \
    --prompt "Please enter your email" \
    --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" \
    --search-default "changeme@example.com" \
    --success-msg "Updated \".infrastructure/conf/traefik/prod/traefik.yml\" with your email."