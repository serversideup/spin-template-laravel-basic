#!/bin/env bash

prompt_and_update_file \
    --title "Configure Let's Encrypt" \
    --details "Let's Encrypt requires an email address to send notifications about SSL renewals." \
    --prompt "Please enter your email" \
    --file "$project_dir/.infrastructure/conf/traefik/prod/traefik.yml" \
    --search-default "changeme@example.com" \
    --success-msg "Updated \".infrastructure/conf/traefik/prod/traefik.yml\" with your email."