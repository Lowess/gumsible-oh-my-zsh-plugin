
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
    ENV_PLUGINS=("-e" "PLUGIN_TASK=${2}")

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
    lowess/drone-molecule:latest
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
