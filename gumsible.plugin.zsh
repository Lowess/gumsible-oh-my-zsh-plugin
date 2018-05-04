
function _gumsible_find_dirname(){
    # Try to find the role's root repository
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

function _gumsible_molecule() {
    # Grab the role's root folder if any...
    local EXEC_DIR=$(_gumsible_find_dirname $(pwd))
    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    local EXEC_DIR_NAME=$(/usr/bin/basename ${EXEC_DIR})

    # Pass the second argument as a command line
    ENV_PLUGINS=("-e" "PLUGIN_COMMAND=${2}")

    case "${2}" in
        init)
            ENV_PLUGINS+=("-e" "PLUGIN_URL=git@bitbucket.org:gumgum/ansible-role-cookiecutter.git")
            ;;
        init)
            ;;
        test|converge)
            # Start a proxy container to cache downloads
            local proxy_cache_container="squid"

            docker start ${proxy_cache_container} 1&> /dev/null || docker run -d \
            --name ${proxy_cache_container} \
            -p 3128:3128 \
            -v ~/.squid/cache:/var/spool/squid3 \
            sameersbn/squid:3.3.8-23 1&> /dev/null
            ;;
    esac

    docker run --rm -it \
    -v ${EXEC_DIR}:/tmp/${EXEC_DIR_NAME} \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w /tmp/${EXEC_DIR_NAME} \
    -v ~/.ssh:/root/.ssh \
    -v ~/.aws:/root/.aws \
    ${ENV_PLUGINS[@]} \
    lowess/drone-molecule:experiment
}

function gumsible(){

    case "$1" in
        molecule)
            _gumsible_molecule $@
            ;;

        *)
            _gumsible_molecule "molecule" $@
            ;;
    esac
}


_gumsible () {
    local -a _1st_arguments

    _1st_arguments=('check' 'converge' 'create' 'dependency' 'destroy' 'idempotence' 'init'
                    'lint' 'list' 'login' 'prepare' 'side' 'syntax' 'test' 'verify')

    _arguments \
        '*:: :->subcmds' && return 0

    if (( CURRENT == 1 )); then
        _describe -t commands "gumsible subcommand" _1st_arguments
        return
    fi

    case "$words[1]" in
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
    esac
}

compdef _gumsible gumsible
