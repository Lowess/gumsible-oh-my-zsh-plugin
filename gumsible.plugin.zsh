
function _gumsible_find_dirname(){
    local path="$1"

    if [[ "${path}" != '/' ]];
    then
        if [[ $(/usr/bin/basename $path) =~ 'ansible-role-' ]];
        then
            echo $path
        else
            _gumsible_find_dirname $(/usr/bin/dirname $path)
        fi
    fi
}

function _gumsible_init() {
    docker run --rm -it \
    -v "${PWD}":/tmp/$(/usr/bin/basename "${PWD}") \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w /tmp/$(/usr/bin/basename "${PWD}") \
    -v ~/.ssh:/root/.ssh \
    lowess/drone-molecule:latest \
    /bin/bash -c 'eval $(ssh-agent -s) > /dev/null \
    ssh-add ~/.ssh/id_rsa;
    molecule init template --url git@bitbucket.org:gumgum/ansible-role-cookiecutter.git'

    # Pre-commit install
    cd $2 && pre-commit install && cd ..
}

function _gumsible_test() {

    local proxy_cache_container="squid"
    local ansible_role_dir=$(_gumsible_find_dirname $(pwd))
    local ansible_role_name=$(/usr/bin/basename ${ansible_role_dir})

    docker start ${proxy_cache_container} 1&> /dev/null || docker run -d \
    --name ${proxy_cache_container} \
    -p 3128:3128 \
    -v ~/.squid/cache:/var/spool/squid3 \
    sameersbn/squid:3.3.8-23 1&> /dev/null

    docker run --rm -it \
    -v ${ansible_role_dir}:/tmp/${ansible_role_name} \
    -v ~/.aws:/root/.aws \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w /tmp/${ansible_role_name} \
    -e PROXY_URL="$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' ${proxy_cache_container})" \
    lowess/drone-molecule:latest \
    $@
}

function gumsible(){

    case "$1" in
        'init')
            _gumsible_init $@
            ;;

        'test')
            _gumsible_test molecule test
            ;;

        'molecule')
            _gumsible_test $@
            ;;
    esac
}


_gumsible () {
    local -a _1st_arguments

    _1st_arguments=('init' 'test' 'molecule')

    _arguments \
        '*:: :->subcmds' && return 0

    if (( CURRENT == 1 )); then
        _describe -t commands "gumsible subcommand" _1st_arguments
        return
    fi

    case "$words[1]" in
    init)
        ;;

    molecule)
        subcmds=(
            'check:Use the provisioner to perform a Dry-Run...'
            'converge:Use the provisioner to configure instances...'
            'create:Use the provisioner to start the instances.'
            'dependency:Manage the roles dependencies.'
            'destroy:Use the provisioner to destroy the instances.'
            'idempotence:Use the provisioner to configure the...'
            'init:Initialize a new role or scenario.'
            'lint:Lint the role.'
            'list:Lists status of instances.'
            'login:Log in to one instance.'
            'prepare:Use the provisioner to prepare the instances...'
            'side-effect:Use the provisioner to perform side-effects...'
            'syntax:Use the provisioner to syntax check the role.'
            'test:Test (lint, destroy, dependency, syntax,...'
            'verify:Run automated tests against instances.'
        )

        _describe 'command' subcmds
        ;;

    pre-commit)
        ;;
    esac
}

compdef _gumsible gumsible
