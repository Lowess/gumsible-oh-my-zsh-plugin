###################################################################
# Script Name    : gumsible.plugin.zsh
# Description    : Wrapper to easily run Ansible Molecule on Docker
# Args           :
# Author         : Florian Dambrine
# Email          : android.florian@gmail.com
###################################################################

# shellcheck disable=SC2148

function __gumsible_list_commands() {

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

function __gumsible_find_dirname() {

    local path="$1"

    if [[ "${path}" != '/' ]];
    then
        if [[ $(/usr/bin/basename "${path}") =~ 'ansible-role-' ]];
        then
            echo "${path}"
        else
            __gumsible_find_dirname "$(/usr/bin/dirname "${path}")"
        fi
    fi
}

function __gumsible_sidecar_containers() {

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

function __gumsible_default_config() {
    # Molecule settings
    GUMSIBLE_MOLECULE_COOKIECUTTER_URL="https//github.com/retr0h/cookiecutter-molecule"
    # Gumsible settings
    GUMSIBLE_SIDECARS_ENABLED="true"
    GUMSIBLE_UPDATES_ENABLED="true"
    # Gumsible Docker settings
    GUMSIBLE_DOCKER_IMAGE_NAME="quay.io/ansible/molecule"
    GUMSIBLE_DOCKER_IMAGE_VERSION="latest"

    # Ansible settings
    ANSIBLE_STRATEGY="linear"
}

function __gumsible_display_config() {
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

function __gumsible_config() {

    local GUMSIBLE_CONFIG_PATH="${1:-${HOME}}/.gumsible"

    if [[ -r ${GUMSIBLE_CONFIG_PATH} ]]; then

        # shellcheck source=/dev/null
        source "${GUMSIBLE_CONFIG_PATH}"

        if [ -z "${1}" ]; then
            echo "~~> ${fg[cyan]:-}Loaded ${GUMSIBLE_CONFIG_PATH} settings successfully.${reset_color:-}"
        else
            echo "~~> ${fg[magenta]:-}Overrode settings using ${GUMSIBLE_CONFIG_PATH}.${reset_color:-}"
        fi

        __gumsible_display_config
    else
        # Load default config only when trying to source ${HOME}/.gumsible
        if [ -z "${1}" ]; then
            echo "~~> ${fg[yellow]:-}Warning ${GUMSIBLE_CONFIG_PATH} file not found, using default settings.${reset_color:-}"
            __gumsible_default_config
            __gumsible_display_config
        fi
    fi
}

function __gumsible_check_updates() {

    local DOCKER_IMG_UPDATE

    echo "~~> ${fg[cyan]:-}Checking docker image updates for ${fg[green]}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${reset_color:-}"

    DOCKER_IMG_UPDATE=$(docker pull "${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION}" | grep -q "Image is up to date")

    if [[ "${DOCKER_IMG_UPDATE}" -eq "0" ]]; then
       echo "  | ~~> ${fg[green]:-}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${fg[cyan]:-}image is already up to date ${reset_color:-}"
    else
       echo "  | ~~> ${fg[green]:-}${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION} ${fg[cyan]:-}image was updated successfully ${reset_color:-}"
    fi
}

function __gumsible_sync_requirements() {

    local EXEC_DIR
    local EXEC_DIR_NAME

    # Grab the role's root folder if any...
    EXEC_DIR=$(__gumsible_find_dirname "$(pwd)")
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

function __gumsible_molecule() {

    # `ARGS`: Command line arguments
    local ARGS=("${@}")
    # `COMMAND`: Command currently being executed
    local COMMAND
    # `COMMANDS`: List of available Molecule commands
    local COMMANDS
    # `EXEC_DIR`: Root folder absolute path from where Molecule should be executed
    local EXEC_DIR
    # `EXEC_DIR_NAME`: Name of root folder (Ansible role name)
    local EXEC_DIR_NAME
    # `SIDECAR_OPTS`: A list of optional Docker arguments populated by Sidecar containers
    local SIDECAR_OPTS=()

    # Grab the role's root folder if any...
    EXEC_DIR=$(__gumsible_find_dirname "$(pwd)")

    #... otherwise default to the current PWD
    if [[ -z "${EXEC_DIR}" ]]; then
        EXEC_DIR="${PWD}"
    fi

    EXEC_DIR_NAME=$(/usr/bin/basename "${EXEC_DIR}")

    # If a the role contains it's own .gumsible file then load it
    __gumsible_config "${EXEC_DIR}"

    if "${GUMSIBLE_UPDATES_ENABLED}"; then
        __gumsible_check_updates
    fi

    # Identify which argument is used
    COMMANDS=$(__gumsible_list_commands)

    for ARG in "${ARGS[@]}"; do
        if [[ "${COMMANDS}" =~ $ARG ]]; then
            COMMAND=${ARG}
        fi
    done

    # Based on the type of command invoked
    case "${COMMAND}" in
        init)
            # Shortcut for init to use the preconfigured Gumsible template
            ARGS=("init" "template" "--url" "${GUMSIBLE_MOLECULE_COOKIECUTTER_URL}" )
            ;;

        dependency | check | test | converge)
            if "${GUMSIBLE_SIDECARS_ENABLED}"; then
                # Docker options to use ssh-agent sidecar container
                __gumsible_sidecar_containers ssh-agent
                SIDECAR_OPTS=("--volumes-from=ssh-agent")
                SIDECAR_OPTS+=("-e" "SSH_AUTH_SOCK=/.ssh-agent/socket")

                case "${COMMAND}" in
                    test | converge)
                        # Docker options to use squid sidecar container
                        __gumsible_sidecar_containers squid
                        SIDECAR_OPTS+=("-e" "PROXY_URL=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' squid)")
                        ;;
                esac
            fi
            ;;
    esac

    docker run --rm -it \
               -v "${EXEC_DIR}:/tmp/${EXEC_DIR_NAME}" \
               -v "/tmp/molecule:/tmp/molecule" \
               -v /var/run/docker.sock:/var/run/docker.sock \
               -v ~/.ssh:/root/.ssh \
               -v ~/.aws:/root/.aws \
               -w "/tmp/${EXEC_DIR_NAME}" \
               -u "root" \
               --entrypoint="molecule" \
               -e "PWD=/tmp/${EXEC_DIR_NAME}" \
               -e "ANSIBLE_STRATEGY=${ANSIBLE_STRATEGY}" \
               "${SIDECAR_OPTS[@]}" \
               "${GUMSIBLE_DOCKER_IMAGE_NAME}:${GUMSIBLE_DOCKER_IMAGE_VERSION}" \
               "${ARGS[@]}"
}

function gumsible(){

    __gumsible_config

    case "$1" in
        # Gumsible sync-requirements
        sync-requirements)
            __gumsible_sync_requirements
            ;;
        # Molecule commands
        *)
            __gumsible_molecule "${@}"
            ;;
    esac
}
