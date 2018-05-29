
function _gumsible_find_dirname() {
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

function _gumsible_sidecar_containers() {

    local SIDECAR_CONTAINER=${1}

    echo "~~> $fg[cyan]Starting sidecar container: $fg[green]${SIDECAR_CONTAINER}$reset_color"
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
            echo "~~> $fg[red]Unknown sidecar container.$reset_color"
            exit 1
            ;;
    esac
}

function __sync_requirements() {

    # Grab the role's root folder if any...
    local EXEC_DIR=$(_gumsible_find_dirname $(pwd))
    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    local EXEC_DIR_NAME=$(/usr/bin/basename ${EXEC_DIR})


    if [ -f ${EXEC_DIR}/molecule/resources/requirements-local.yml ]; then
        echo "~~> $fg[cyan]Syncing: $fg[yellow]requirements-drone.yml$reset_color from $fg[magenta]requirements-local.yml $reset_color"

        sed 's/git@bitbucket.org:/https:\/\/bitbucket.org\//g' \
            ${EXEC_DIR}/molecule/resources/requirements-local.yml > \
            ${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp

        git --no-pager diff ${EXEC_DIR}/molecule/resources/requirements-drone.yml \
            ${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp

        if [[ $? -eq "0" ]]; then
            rm ${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp
            echo "~~> $fg[yellow]requirements-drone.yml$reset_color and $fg[magenta]requirements-local.yml$reset_color were already in sync.$reset_color"
        else
            mv ${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp \
                ${EXEC_DIR}/molecule/resources/requirements-drone.yml
            echo "~~> $fg[yellow]requirements-drone.yml$reset_color and $fg[magenta]requirements-local.yml$reset_color $fg[green]are now in sync.$reset_color"
        fi

    else
        echo "~~> $fg[red]Could not find molecule/resources/requirements-local.yml. Make sure you inside a an ansible role.$reset_color"
        exit 2
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

        sync-requirements)
            __sync_requirements
            ;;

        *)
            _gumsible_molecule "molecule" $@
            ;;
    esac
}
