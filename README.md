# heroku-docker

Turn Heroku apps into Docker images

## Installation

    $ heroku plugins:install https://github.com/ddollar/heroku-docker

## Prerequsites

You'll need a working `docker` CLI and a valid `DOCKER_HOST`.
You should be able to `docker ps` successfully.

## Usage

#### Build a Docker image from your Heroku app

    $ heroku docker:build -a myapp
    Sending build context to Docker daemon 3.584 kB
    Sending build context to Docker daemon
    Step 0 : FROM ddollar/heroku-bamboo
     ---> 66f87f3cd8fb
    ...
    Step 32 : CMD thin -p 5000 -e ${RACK_ENV:-production} -R $HEROKU_RACK start
     ---> Running in 2ae2bfff2db2
     ---> e22b7e884e9a
    Removing intermediate container 2ae2bfff2db2
    Successfully built e22b7e884e9a
    Built image myapp

#### Get an env-file suitable for `docker run`

    $ heroku docker:env -a myapp
    FOO=bar

#### Build a Docker image from a Heroku app and then run it using the app's config vars

    $ heroku docker:run -a myapp
    >> Thin web server (v1.2.7 codename No Hup)
    >> Maximum connections set to 1024
    >> Listening on 0.0.0.0:5000, CTRL+C to stop

#### Find your app's web port in Docker

    $ docker ps
    CONTAINER ID        IMAGE               COMMAND                CREATED             STATUS              PORTS                     NAMES
    131c1ea36d2f        myapp:latest        /bin/sh -c 'thin -p    1 seconds ago       Up 2 seconds        0.0.0.0:49164->5000/tcp   suspicious_lovelace

#### Test your app

    $ curl http://127.0.0.1:49164
    ok

## Copyright

David Dollar

## License

MIT
