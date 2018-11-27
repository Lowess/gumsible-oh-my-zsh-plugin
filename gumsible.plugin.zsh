# shellcheck disable=SC2148

function _gumsible_find_dirname() {

    local path="$1"

    if [[ "${path}" != '/' ]];
    then
        if [[ $(/usr/bin/basename "${path}") =~ 'ansible-role-' ]];
        then
            echo "${path}"
        else
            _gumsible_find_dirname "$(/usr/bin/dirname "${path}")"
        fi
    fi
}

function _gumsible_list_commands() {

    local GUMSIBLE_MOLECULE_COMMANDS

    GUMSIBLE_MOLECULE_COMMANDS=$(docker run --rm -it \
                                                  -v "${EXEC_DIR}:/tmp/${EXEC_DIR_NAME}" \
                                                  --entrypoint="molecule" \
                                                  "${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION}" \
                                                  "--help" \
                                        | grep -A100 'Commands' \
                                        | tail -n +2 \
                                        | awk '{ if ($2) print $1; }')
    echo "${GUMSIBLE_MOLECULE_COMMANDS}"
}

function _gumsible_sidecar_containers() {

    local SIDECAR_CONTAINER=${1}

    echo "~~> ${fg[cyan]:-}Starting sidecar container: ${fg[green]:-}${SIDECAR_CONTAINER}${reset_color:-}"
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
            lowess/squid:latest 1&> /dev/null
            ;;
        *)
            echo "~~> ${fg[red]:-}Unknown sidecar container.${reset_color:-}"
            return 1
            ;;
    esac
}

function __gumsible_config() {

    local GUMSIBLE_CONFIG_PATH="${HOME}/.gumsible"

    # Molecule settings
    GUMSIBLE_MOLECULE_COOKIECUTTER_URL="https//github.com/retr0h/cookiecutter-molecule"
    # Gumsible settings
    GUMSIBLE_SIDECARS_ENABLED="true"
    GUMSIBLE_UPDATES_ENABLED="true"
    # Gumsible Docker settings
    GUMSIBLE_DOCKER_IMAGE_NAME="retr0h/molecule"
    GUMSIBLE_DOCKER_IMAGE_VERSION="latest"

    # Ansible settings
    ANSIBLE_STRATEGY="linear"

    if [[ -r ${GUMSIBLE_CONFIG_PATH} ]]; then
        echo "~~> ${fg[cyan]:-}Loaded ~/.gumsible settings successfully.${reset_color:-}"

        # shellcheck source=/dev/null
        source "${GUMSIBLE_CONFIG_PATH}"
    else
        echo "~~> ${fg[yellow]:-}Warning ~/.gumsible file not found, using default settings.${reset_color:-}"
    fi

    # Molecule settings
    echo "  | ~~> GUMSIBLE_MOLECULE_COOKIECUTTER_URL = ${GUMSIBLE_MOLECULE_COOKIECUTTER_URL}"
    # Gumsible settings
    echo "  | ~~> GUMSIBLE_SIDECARS_ENABLED = ${GUMSIBLE_SIDECARS_ENABLED}"
    echo "  | ~~> GUMSIBLE_UPDATES_ENABLED = ${GUMSIBLE_UPDATES_ENABLED}"
    # Gumsible Docker settings
    echo "  | ~~> GUMSIBLE_DOCKER_IMAGE_NAME = ${GUMSIBLE_DOCKER_IMAGE_NAME}"
    echo "  | ~~> GUMSIBLE_DOCKER_IMAGE_VERSION = ${GUMSIBLE_DOCKER_IMAGE_VERSION}"
    # Ansible settings
    echo "  | ~~> ANSIBLE_STRATEGY = ${ANSIBLE_STRATEGY}"
}

function __check_image_updates() {

    local DOCKER_IMG_UPDATE

    echo "~~> ${fg[cyan]:-}Checking docker image updates for ${fg[green]}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${reset_color:-}"

    DOCKER_IMG_UPDATE=$(docker pull "${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION}" | grep -q "Image is up to date")

    if [[ "${DOCKER_IMG_UPDATE}" -eq "0" ]]; then
       echo "  | ~~> ${fg[green]:-}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${fg[cyan]:-}image is already up to date ${reset_color:-}"
    else
       echo "  | ~~> ${fg[green]:-}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${fg[cyan]:-}image was updated successfully ${reset_color:-}"
    fi
}

function __sync_requirements() {

    local EXEC_DIR
    local EXEC_DIR_NAME

    # Grab the role's root folder if any...
    EXEC_DIR=$(_gumsible_find_dirname "$(pwd)")
    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    EXEC_DIR_NAME=$(/usr/bin/basename "${EXEC_DIR}")

    if [ -f "${EXEC_DIR}/molecule/resources/requirements-local.yml" ]; then
        echo "~~> ${fg[cyan]:-}Syncing: ${fg[yellow]:-}requirements-drone.yml${reset_color:-} from ${fg[magenta]:-}requirements-local.yml ${reset_color:-}"

        sed 's/git@bitbucket.org:/https:\/\/bitbucket.org\//g' \
            "${EXEC_DIR}/molecule/resources/requirements-local.yml" > \
            "${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp"

        if diff "${EXEC_DIR}/molecule/resources/requirements-drone.yml" \
            "${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp"
        then
            rm "${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp"
            echo "~~> ${fg[yellow]}requirements-drone.yml${reset_color:-} and ${fg[magenta]:-}requirements-local.yml${reset_color:-} were already in sync.${reset_color:-}"
        else
            mv "${EXEC_DIR}/molecule/resources/requirements-drone.yml.tmp" \
                "${EXEC_DIR}/molecule/resources/requirements-drone.yml"
            echo "~~> ${fg[yellow]}requirements-drone.yml${reset_color:-} and ${fg[magenta]:-}requirements-local.yml${reset_color:-} ${fg[green]}are now in sync.${reset_color:-}"
        fi

    else
        echo "~~> ${fg[red]:-}Could not find molecule/resources/requirements-local.yml. Make sure you inside a an ansible role.${reset_color:-}"
        return 2
    fi
}

function _gumsible_molecule() {

    local EXEC_DIR
    local EXEC_DIR_NAME
    local SSH_AGENT_SIDECAR_OPTS=()
    local COMMANDS=$(_gumsible_list_commands)
    local OPTIONS=("${@}")
    local COMMAND

    if "${GUMSIBLE_UPDATES_ENABLED}"; then
        __check_image_updates
    fi

    # Grab the role's root folder if any...
    EXEC_DIR=$(_gumsible_find_dirname "$(pwd)")
    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    EXEC_DIR_NAME=$(/usr/bin/basename "${EXEC_DIR}")

    # Docker options to use ssh-agent sidecar container
    if "${GUMSIBLE_SIDECARS_ENABLED}"; then
        _gumsible_sidecar_containers ssh-agent
        SSH_AGENT_SIDECAR_OPTS=("--volumes-from=ssh-agent")
        SSH_AGENT_SIDECAR_OPTS+=("-e" "SSH_AUTH_SOCK=/.ssh-agent/socket")
    fi

    for OPTION in "${OPTIONS[@]}"; do
        if [[ "${COMMANDS}" =~ $OPTION ]]; then
            COMMAND=${OPTION}
        fi
    done

    # Based on the type of command invoked
    case "${COMMAND}" in
        init)
            # Shortcut for init to use the preconfigured Gumsible template
            OPTIONS=("init" "template" "--url" "${GUMSIBLE_MOLECULE_COOKIECUTTER_URL}" )
            ;;
        test | converge)
            if "${GUMSIBLE_SIDECARS_ENABLED}"; then
                # Docker options to use squid sidecar container
                _gumsible_sidecar_containers squid
                ENV_PLUGINS+=("-e" "PROXY_URL=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' squid)")
            fi
            ;;
    esac

    docker run --rm -it \
               -v "${EXEC_DIR}:/tmp/${EXEC_DIR_NAME}" \
               -v /var/run/docker.sock:/var/run/docker.sock \
               -v ~/.ssh:/root/.ssh \
               -v ~/.aws:/root/.aws \
               -w "/tmp/${EXEC_DIR_NAME}" \
               -u "root" \
               --entrypoint="molecule" \
               -e "PWD=/tmp/${EXEC_DIR_NAME}" \
               -e "ANSIBLE_STRATEGY=${ANSIBLE_STRATEGY}" \
               "${SSH_AGENT_SIDECAR_OPTS[@]}" \
               "${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION}" \
               "${OPTIONS[@]}"
}

function gumsible(){

    __gumsible_config

    case "$1" in
        # Gumsible sync-requirements
        sync-requirements)
            __sync_requirements
            ;;
        *)
            _gumsible_molecule "${@}"
            ;;
    esac
}
