#/bin/env bash
set -e
PHP_IMAGE="serversideup/php:8.3-cli-alpine"
project_dir=${1:-"laravel"}
docker pull $PHP_IMAGE
docker run --rm -w /var/www/html -v $(pwd):/var/www/html --user "${SPIN_USER_ID}:${SPIN_GROUP_ID}" -e "SHOW_WELCOME_MESSAGE=false" $PHP_IMAGE composer --no-cache create-project laravel/laravel "$@"
docker run --rm -v "$project_dir:/var/www/html" -e "SHOW_WELCOME_MESSAGE=false" $PHP_IMAGE composer --working-dir=/var/www/html/ require serversideup/spin --dev