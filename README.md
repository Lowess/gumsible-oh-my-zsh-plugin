# :candy: Gumsible oh-my-zsh-plugin

### Using Oh-My-Zsh

If you are using Linux or Mac OS X, Oh-My-Zsh is a great tool to manage your ZSH configuration.

Most of the GumGum Ops team uses Oh-My-Zsh, and if you see people using shortcuts in their terminal, the magic comes from here!

### Oh-My-Zsh Gumsible plugin
The Gumsible Oh-My-Zsh plugin is available on GitHub at https://github.com/Lowess/gumsible-oh-my-zsh-plugin.

Currently it offers the following wrappers:

* `gumsible check`: Shortcut to run `molecule check`
* `gumsible converge`: Shortcut to run `molecule converge`
* `gumsible create`: Shortcut to run `molecule create`
* `gumsible dependency`: Shortcut to run `molecule dependency`
* `gumsible destroy`: Shortcut to run `molecule destroy`
* `gumsible idempotence`: Shortcut to run `molecule idempotence`
* `gumsible init`: Shortcut to `molecule init`. Used to initialize a new Ansible role from a [Cookiecutter template](https://github.com/audreyr/cookiecutter) including the [Molecule](http://molecule.readthedocs.io/en/latest/index.html) test framework.
* `gumsible lint`: Shortcut to run `molecule lint`
* `gumsible list`: Shortcut to run `molecule list`
* `gumsible login <host>`: Shortcut to run `molecule login`
* `gumsible molecule <cmd>`: Runs `molecule` commands
* `gumsible prepare`: Shortcut to run `molecule prepare`
* `gumsible side-effect`: Shortcut to run `molecule side-effect`
* `gumsible syntax`: Shortcut to run `molecule syntax`
* `gumsible test`: Shortcut to run `molecule test`
* `gumsible verify`: Shortcut to run `molecule verify`

It is not part of the official plugin list, so you need to install it manually:

* Edit your `~/.zshrc` and add `gumsible` to the list of plugins to enable:

`plugins=( ... gumsible )`

In the command line, change to oh-my-zsh’s custom plugin directory and clone the repository:

`cd ~/.oh-my-zsh/custom/plugins && git clone https://github.com/Lowess/gumsible-oh-my-zsh-plugin gumsible && cd && . ~/.zshrc`

### Plugin configuration (optional)

By default you can use the plugin as it is, but you might want to customize the plugin behavior. You can change plugin settings by dropping a `.gumsible` file under your `HOME` folder (`~/.gumsible`). This repository contains an example configuration file that you can copy (you can comment / uncomment variables using `#`).

The settings file is a `shell` script sourced by the plugin.

```sh
#-- A Cookiecutter URL to init the new molecule role from:
#   Examples:
#     Public git repo: GUMSIBLE_MOLECULE_COOKIECUTTER_URL='https//github.com/retr0h/cookiecutter-molecule'
#     Private git repo: GUMSIBLE_MOLECULE_COOKIECUTTER_URL='git@bitbucket.org:gumgum/ansible-role-cookiecutter.git'
GUMSIBLE_MOLECULE_COOKIECUTTER_URL='https//github.com/retr0h/cookiecutter-molecule'

#-- Boolean to specify if you want to start sidecar containers (ssh-agent companion and squid proxy)
GUMSIBLE_SIDECARS_ENABLED='true'

#-- Boolean to check for newly pushed `GUMSIBLE_DOCKER_IMAGE_NAME`
GUMSIBLE_UPDATES_ENABLED='true'

#-- Molecule Docker image to use
GUMSIBLE_DOCKER_IMAGE_NAME='retr0h/molecule'

#-- Molecule Docker version
GUMSIBLE_DOCKER_IMAGE_VERSION='latest'
```

