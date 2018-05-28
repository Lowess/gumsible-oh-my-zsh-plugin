
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

function _gumsible_sidecar_containers(){

    local SIDECAR_CONTAINER=${1}

    echo "Starting sidecar container ${SIDECAR_CONTAINER}"
    case ${SIDECAR_CONTAINER} in
        ssh-agent)
            # Using a sidecar ssh-agent to forward SSH_AUTH_SOCK
            local SSH_AGENT_SIDECAR="ssh-agent"

            # Start the ssh-agent container. If already started, do not prompt for passphrase
            docker start ${SSH_AGENT_SIDECAR} 1&> /dev/null || \
            (
                docker run -d \
                --name ${SSH_AGENT_SIDECAR} \
                nardeas/ssh-agent 1&> /dev/null \
            && \
                docker run -it --rm \
                --volumes-from=ssh-agent \
                -v ~/.ssh:/.ssh \
                nardeas/ssh-agent \
                ssh-add /root/.ssh/id_rsa
            )
            ;;

        squid)
            # Start a proxy container to cache downloads
            local PROXY_CACHE_SIDECAR="squid"

            docker start ${PROXY_CACHE_SIDECAR} 1&> /dev/null || docker run -d \
            --name ${PROXY_CACHE_SIDECAR} \
            -p 3128:3128 \
            -v ~/.squid:/var/spool/squid3 \
            lowess/squid:3.5.27 1&> /dev/null
            ;;
        *)
            echo "Unknown sidecar container... abort"
            exit 1
            ;;
    esac
}

function _gumsible_molecule() {
    # Grab the role's root folder if any...
    local EXEC_DIR=$(_gumsible_find_dirname $(pwd))
    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    local EXEC_DIR_NAME=$(/usr/bin/basename ${EXEC_DIR})


    # Docker options to use ssh-agent sidecar container
    _gumsible_sidecar_containers ssh-agent
    SSH_AGENT_SIDECAR_OPTS=("--volumes-from=ssh-agent")
    SSH_AGENT_SIDECAR_OPTS+=("-e" "SSH_AUTH_SOCK=/.ssh-agent/socket")

    # Pass the second argument as a command line
    ENV_PLUGINS=("-e" "PLUGIN_TASK=${2}")
    OPTIONS=""

    case "${2}" in
        init)
            ENV_PLUGINS+=("-e" "PLUGIN_URL=git@bitbucket.org:gumgum/ansible-role-cookiecutter.git")
            ;;
        login)
            ENV_PLUGINS+=("-e" "PLUGIN_HOST=${3}")
            ;;
        test | converge)
            # Docker options to use squid sidecar container
            _gumsible_sidecar_containers squid
            ENV_PLUGINS+=("-e" "PROXY_URL=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' squid)")
            OPTIONS="${@:3}"
            ;;
    esac

    docker run --rm -it \
    -v ${EXEC_DIR}:/tmp/${EXEC_DIR_NAME} \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ~/.ssh:/root/.ssh \
    -v ~/.aws:/root/.aws \
    -w /tmp/${EXEC_DIR_NAME} \
    ${SSH_AGENT_SIDECAR_OPTS[@]} \
    ${ENV_PLUGINS[@]} \
    lowess/drone-molecule:latest \
    ${OPTIONS[@]}
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
