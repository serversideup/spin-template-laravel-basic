# Official Spin Laravel Template

> [!WARNING]  
> This repo is experimental and currently under construction. Check back for more details later 👷‍♂️🚧🏗️

## Getting started
To use this template, you must have [Spin](https://serversideup.net/open-source/spin/docs) installed.

```bash
spin new laravel my-laravel-app
```

> [!CAUTION]
> There are settings to change before you can use this template.

### Configure your `/etc/hosts` file
We have the development URL set up to work under the `*.dev.test` domain. This also includes wildcard certificates that will trust connections on this domain as well.

To get your machine to recognize these domains, add the following to your `/etc/hosts` file:

```bash
127.0.0.1 laravel.dev.test
127.0.0.1 mailpit.dev.test
```
Change `laravel` to your app name or whatever you would like to use. For the best experience, just make sure it ends in `.dev.test`.

### `docker-compose.dev.yml`
This file is used for development. You'll need to make the following changes:

#### Change the development Traefik domain
If you want HTTPS to work, you need to let Let's Encrypt know what domain you are using. You can do this by changing the `docker-compose.prod.yml` file.

```yaml
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.laravel.rule=Host(`laravel.dev.test`)"
```

### `docker-compose.prod.yml`
This file is used for production deployments. You'll need to make the following changes:

#### Change the image name
If you're using CI/CD, you'll likely want to change the image name in the `docker-compose.prod.yml` file.

```yaml
  php:
    image: ${SPIN_IMAGE_NAME} # 👈 Change this if you're not using `spin deploy`
```

Set this value to the published image with your repository.

#### Change the production Traefik domain
If you want HTTPS to work, you need to let Let's Encrypt know what domain you are using. You can do this by changing the `docker-compose.prod.yml` file.

```yaml
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.my-php-app.rule=Host(`myapp.example.com`)"
```

Change `myapp.example.com` to your domain name.

### Verify the Traefik config name
If you run `spin deploy`, we include a variable called `SPIN_TRAEFIK_CONFIG_MD5_HASH` that ensures the Swarm Configuration is always up to date.

If you're not using `spin deploy`, you may need to change this value:

```yaml
configs:
  traefik:
    name: "traefik-${SPIN_TRAEFIK_CONFIG_MD5_HASH}.yml"
    file: ./.infrastructure/conf/traefik/prod/traefik.yml
```

### `template/.infrastructure/conf/traefik/dev/certificates`
We provide certificates by default. If you'd like to trust these certificates, you need to install the CA on your machine.

**Download the CA Certificate:**
- https://serversideup.net/ca/

You can change these files out if you'd like to use your own certificates.

### `template/.infrastructure/conf/traefik/prod/traefik.yml`
If you'd like Let's Encrypt to work, you need to change the email address in the `traefik/prod/traefik.yml` file.

```yml
certificatesResolvers:
  letsencryptresolver:
    acme:
      email: "changeme@example.com"
```

Change `changeme@example.com` to a valid email address.

## Default configuration
By default, this template is configured to work with `spin deploy` out of the box. If you prefer to use CI/CD to deploy your files (which isn't a bad idea), you will need to make your own changes to these files. These files should still give you a good head start.

Before running `spin deploy`, ensure you configured:

1. You deployed a server and have SSH access
1. Set variables in `.spin.yml`
1. Added your server in `.spin-inventory.yml`
1. You successfully completed `spin provision`

Once the steps above are complete, you can run `spin deploy` to deploy your application:

```bash
spin deploy <environment-name>
```