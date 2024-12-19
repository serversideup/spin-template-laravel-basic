#!/bin/bash

# Capture Spin Variables
SPIN_ACTION=${SPIN_ACTION:-"install"}
SPIN_PHP_VERSION="${SPIN_PHP_VERSION:-8.4}"
SPIN_PHP_DOCKER_IMAGE="${SPIN_PHP_DOCKER_IMAGE:-serversideup/php:${SPIN_PHP_VERSION}-cli}"

# Set project variables
spin_template_type="open-source"
javascript_package_manager="yarn"
project_dir=${SPIN_PROJECT_DIRECTORY:-"$(pwd)/template"}
php_dockerfile="Dockerfile"
docker_compose_database_migration="false"

# Initialize the service variables
horizon=""
queue=""
reverb=""
schedule=""
sqlite=""
mysql=""
mariadb=""
postgresql=""
redis=""
use_github_actions=""

###############################################
# Functions
###############################################
add_php_extensions() {
    echo "${BLUE}Adding custom PHP extensions...${RESET}"
    local dockerfile="$project_dir/$php_dockerfile"
    
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

configure_sqlite() {
    local service_name="sqlite"
    local init_sqlite=true
    local laravel_default_sqlite_database_path="$project_dir/database/database.sqlite"
    local spin_sqllite_database_path="$project_dir/.infrastructure/volume_data/sqlite/database.sqlite"

    if [ "$spin_template_type" == "pro" ]; then
        merge_blocks "$service_name"
    fi

    if [[ "$SPIN_ACTION" == "init" ]] && grep -q 'DB_CONNECTION=sqlite' "$SPIN_PROJECT_DIRECTORY/.env"; then
        echo "${BOLD}${RED}⚠️  WARNING ⚠️${RESET}"
        echo "👉 We detected SQLite being used on this project."
        echo "👉 We need to update the .env file to use the correct path."
        echo "${BOLD}${RED}🚨 This means you may need to manually move your data to the path for the database.${RESET}"
        echo ""
        read -n 1 -r -p "${BOLD}${YELLOW} Would you like us to automatically configure SQLite for you? [Y/n]${RESET} " response
        echo ""

        if [[ $response =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "${BOLD}${YELLOW}🚨 You will need to manually move your SQLite database to the correct path.${RESET}"
            echo "${BOLD}${YELLOW}🚨 The path is: ${RESET}${spin_sqllite_database_path}"
            echo ""
            init_sqlite=false
            add_user_todo_item "Move your SQLite database to \"${spin_sqllite_database_path}\"."
        fi
    fi

    if [ "$init_sqlite" == true ]; then
        # Create the SQLite database folder
        mkdir -p "$project_dir/.infrastructure/volume_data/sqlite"

        echo "$service_name: Updating the Laravel .env and .env.example files..."
        line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_CONNECTION=sqlite"
        line_in_file --action after --file "$project_dir/.env" --file "$project_dir/.env.example" "DB_CONNECTION" "DB_DATABASE=/var/www/html/.infrastructure/volume_data/sqlite/database.sqlite"

        # Check if the default Laravel SQLite database exists and the Spin SQLite database doesn't
        if [[ -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqllite_database_path" ]]; then
            echo "${BLUE}Moving existing SQLite database to new location...${RESET}"
            mv "$laravel_default_sqlite_database_path" "$spin_sqllite_database_path"
            echo "SQLite database moved successfully."
        elif [[ ! -f "$laravel_default_sqlite_database_path" && ! -f "$spin_sqllite_database_path" && "$instal" ]]; then
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

initialize_git_repository() {
    local current_dir=""
    current_dir=$(pwd)

    cd "$project_dir" || exit
    echo "Initializing Git repository..."
    git init

    cd "$current_dir" || exit
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
        echo "${BLUE}Installing Node dependencies with ${javascript_package_manager}...${RESET}"
        if ! $COMPOSE_CMD run --no-deps --rm --remove-orphans node ${javascript_package_manager} install; then
            echo "${BOLD}${RED}Error: Failed to install node dependencies.${RESET}" >&2
            return 1
        fi
        echo "Node dependencies installed successfully."
    fi
}

process_selections() { 
    [[ $sqlite ]] && configure_sqlite
    
    if [ "$spin_template_type" = "pro" ]; then
        [[ $schedule ]] && configure_schedule
        [[ $mysql ]] && configure_mysql
        [[ $mariadb ]] && configure_mariadb
        [[ $postgresql ]] && configure_postgresql
        [[ $redis ]] && configure_redis
        [[ $horizon ]] && configure_horizon
        [[ $queue ]] && configure_queue
        [[ $reverb ]] && configure_reverb
        [[ $use_github_actions ]] && configure_github_actions
    fi
    echo "Services configured."
}

select_database() {
    local selection_made=false
    while ! $selection_made; do
        clear
        echo "${BOLD}${YELLOW}What database engine(s) would you like to use?${RESET}"
        echo -e "${sqlite:+$BOLD$BLUE}1) SQLite${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            echo -e "${mysql:+$BOLD$BLUE}2) MySQL${RESET}"
            echo -e "${mariadb:+$BOLD$BLUE}3) MariaDB${RESET}"
            echo -e "${postgresql:+$BOLD$BLUE}4) PostgreSQL${RESET}"
            if [[ $horizon ]]; then
                echo -e "${BOLD}${BLUE}5) Redis (Required for Horizon)${RESET}"
            else
                echo -e "${redis:+$BOLD$BLUE}5) Redis${RESET}"
            fi
        else
            echo -e "${DIM}2) MySQL (Pro)${RESET}"
            echo -e "${DIM}3) MariaDB (Pro)${RESET}"
            echo -e "${DIM}4) PostgreSQL (Pro)${RESET}"
            echo -e "${DIM}5) Redis (Pro)${RESET}"
        fi
        show_spin_pro_notice
        echo "Press a number to select/deselect. Press ${BOLD}${BLUE}ENTER${RESET} to continue."

        read -s -n 1 key
        case $key in
            1) [[ $sqlite ]] && sqlite="" || sqlite="1" ;;
            2) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $mysql ]] && mysql="" || mysql="1"
                fi
                ;;
            3) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $mariadb ]] && mariadb="" || mariadb="1"
                fi
                ;;
            4) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $postgresql ]] && postgresql="" || postgresql="1"
                fi
                ;;
            5) 
                if [ "$spin_template_type" = "pro" ]; then
                    if [[ ! $horizon ]]; then
                        [[ $redis ]] && redis="" || redis="1"
                    fi
                fi
                ;;
            '') 
                if [ "$spin_template_type" = "pro" ] && [[ $horizon && ! $redis ]]; then
                    echo -e "${RED}Redis is required for Horizon. Redis has been automatically selected.${RESET}"
                    redis="1"
                    read -n 1 -s -r -p "Press any key to continue..."
                else
                    selection_made=true
                fi
                ;;
        esac
    done
}

select_features() {
    while true; do
        clear
        echo "${BOLD}${YELLOW}Select which Laravel features you'd like to use:${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            echo -e "${schedule:+$BOLD$BLUE}1) Task Scheduling${RESET}"
            echo -e "${horizon:+$BOLD$BLUE}2) Horizon${RESET}"
            echo -e "${queue:+$BOLD$BLUE}3) Queues (without Redis)${RESET}"
            echo -e "${reverb:+$BOLD$BLUE}4) Reverb${RESET}"
        else
            echo -e "${DIM}1) Task Scheduling (Pro)${RESET}"
            echo -e "${DIM}2) Horizon (Pro)${RESET}"
            echo -e "${DIM}3) Queues (Pro)${RESET}"
            echo -e "${DIM}4) Reverb (Pro)${RESET}"
        fi
        show_spin_pro_notice
        echo "Press a number to select/deselect."
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."

        read -s -r -n 1 key
        case $key in
            1) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $schedule ]] && schedule="" || schedule="1"
                fi
                ;;
            2) 
                if [ "$spin_template_type" = "pro" ]; then
                    if [[ $horizon ]]; then
                        horizon=""
                        redis=""
                    else
                        horizon="1"
                        redis="1"
                    fi
                fi
                ;;
            3) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $queue ]] && queue="" || queue="1"
                fi
                ;;
            4) 
                if [ "$spin_template_type" = "pro" ]; then
                    [[ $reverb ]] && reverb="" || reverb="1"
                fi
                ;;
            '') break ;;
        esac
    done
}

select_github_actions() {
    while true; do
        clear
        echo "${BOLD}${YELLOW}Would you like to use GitHub Actions?${RESET}"
        if [ "$spin_template_type" = "pro" ]; then
            if [ "$use_github_actions" = "1" ]; then
                echo -e "${BOLD}${BLUE}1) Yes${RESET}"
                echo "2) No"
            else
                echo "1) Yes"
                echo -e "${BOLD}${BLUE}2) No${RESET}"
            fi
        else
            echo -e "${DIM}1) Yes (Pro)${RESET}"
            echo -e "${BOLD}${BLUE}2) No${RESET}"
            show_spin_pro_notice
        fi
        echo "Press a number to select/deselect."
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue."

        read -s -n 1 key
        case $key in
            1) 
                if [ "$spin_template_type" = "pro" ]; then
                    use_github_actions="1"
                fi
                ;;
            2) use_github_actions="" ;;
            '') break ;;
        esac
    done
}

select_javascript_package_manager() {
    if [ "$spin_template_type" = "pro" ]; then
        while true; do
            clear
            echo "${BOLD}${YELLOW}Choose your JavaScript package manager:${RESET}"
            if [ "$javascript_package_manager" = "yarn" ]; then
                echo -e "${BOLD}${BLUE}1) yarn${RESET}"
                echo "2) npm"
            else
                echo "1) yarn"
                echo -e "${BOLD}${BLUE}2) npm${RESET}"
            fi
            echo "Press a number to select."
            echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue."

            read -s -n 1 key
            case $key in
                1) javascript_package_manager="yarn" ;;
                2) javascript_package_manager="npm" ;;
                '') break ;;
            esac
        done
    else
        # For open-source, only yarn is available
        javascript_package_manager="yarn"
        clear
        echo "${BOLD}${YELLOW}Choose your JavaScript package manager:${RESET}"
        echo -e "${BOLD}${BLUE}1) yarn${RESET}"
        echo -e "${DIM}2) npm (Pro)${RESET}"
        show_spin_pro_notice
        echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or skip."

        read -s -n 1 key
        case $key in
            '') ;;
            *) select_javascript_package_manager ;;
        esac
    fi
}

select_php_extensions() {
    clear
    echo "${BOLD}${YELLOW}What PHP extensions would you like to include?${RESET}"
    echo ""
    echo "${BLUE}Default extensions:${RESET}"
    echo "ctype, curl, dom, fileinfo, filter, hash, mbstring, mysqli,"
    echo "opcache, openssl, pcntl, pcre, pdo_mysql, pdo_pgsql, redis,"
    echo "session, tokenizer, xml, zip"
    echo ""
    echo "${BLUE}See available extensions:${RESET}"
    echo "https://serversideup.net/docker-php/available-extensions"
    echo ""
    echo "Enter additional extensions as a comma-separated list (no spaces).${RESET}"
    echo "Example: gd,imagick,intl"
    echo ""
    echo "${BOLD}${YELLOW}Enter comma separated extensions below or press ${BOLD}${BLUE}ENTER${RESET} ${BOLD}${YELLOW}to use default extensions.${RESET}"
    read -r extensions_input

    # Remove spaces and split into array
    IFS=',' read -r -a php_extensions <<< "${extensions_input// /}"

    # Print selected extensions for confirmation
    while true; do
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
            echo "${BOLD}${YELLOW}Are these selections correct?${RESET}"
            echo "Press ${BOLD}${BLUE}ENTER${RESET} to continue or ${BOLD}${BLUE}any other key${RESET} to go back and change selections."
            read -n 1 -s -r key
            echo

            if [[ $key == "" ]]; then
                echo "${GREEN}Continuing with selected extensions...${RESET}"
                break
            else
                echo "${YELLOW}Returning to extension selection...${RESET}"
                select_php_extensions
                return
            fi
        else
            break
        fi
    done
}

set_colors() {
    if [[ -t 1 ]]; then
        RAINBOW="
            $(printf '\033[38;5;196m')
            $(printf '\033[38;5;202m')
            $(printf '\033[38;5;226m')
            $(printf '\033[38;5;082m')
            "
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        DIM=$(printf '\033[2m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RAINBOW=""
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        DIM=""
        BOLD=""
        RESET=""
    fi
}

show_spin_pro_notice() {
    if [ "$spin_template_type" != "pro" ]; then
        echo
        echo "${BOLD}${GREEN}Unlock Pro features at 👉 https://getspin.pro${RESET}"
        echo
    fi
}

###############################################
# Main
###############################################

set_colors
select_php_extensions
select_features
select_javascript_package_manager
select_database
select_github_actions

# Clean up the screen before moving forward
clear

# Set PHP Version of Project
line_in_file --action replace --file "$project_dir/$php_dockerfile" "FROM serversideup" "FROM serversideup/php:${SPIN_PHP_VERSION}-fpm-nginx-alpine AS base"

# Add PHP Extensions if available
if [ ${#php_extensions[@]} -gt 0 ]; then
    add_php_extensions
fi

# Install Composer dependencies
if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
    docker pull "$SPIN_PHP_DOCKER_IMAGE"

    if [[ "$SPIN_ACTION" == "init" ]]; then
        echo "Re-installing composer dependencies..."
        docker compose run --rm --build \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
            php \
            composer install

        echo "Installing Spin..."
        docker compose run --rm --build --no-deps --remove-orphans \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
                php \
                composer require serversideup/spin --dev
    else
        echo "Installing Spin..."
        docker run --rm \
            -v "$project_dir:/var/www/html" \
            --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" \
            -e COMPOSER_CACHE_DIR=/dev/null \
            -e "SHOW_WELCOME_MESSAGE=false" \
            "$SPIN_PHP_DOCKER_IMAGE" \
            composer require serversideup/spin --dev
    fi
fi

# Process the user selections
process_selections

if [ "$spin_template_type" == "pro" ]; then
    # Configure Vite
    if [ -f "$project_dir/vite.config.js" ]; then
        configure_vite
    fi

    # Configure APP_URL
    line_in_file --action replace --file "$project_dir/.env" --file "$project_dir/.env.example" "APP_URL" "APP_URL=https://laravel.dev.test"

    configure_mailpit
fi

# Configure Server Contact
line_in_file --action exact --ignore-missing --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" "changeme@example.com" "$SERVER_CONTACT"
line_in_file --action exact --ignore-missing --file "$project_dir/.spin.yml" "changeme@example.com" "$SERVER_CONTACT"

if [[ "$SPIN_INSTALL_DEPENDENCIES" == "true" ]]; then
    install_node_dependencies

    if [[ "$docker_compose_database_migration" == "true" ]]; then
        initialize_database_service
    fi
fi

if [[ ! -d "$project_dir/.git" ]]; then
    initialize_git_repository
fi

# Export actions so it's available to the main Spin script
export SPIN_USER_TODOS