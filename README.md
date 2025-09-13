<p align="center">
    <a href="https://www.linux.org/" alt="Linux">
        <img src="https://img.shields.io/badge/Linux-%23.svg?logo=linux&color=FCC624&logoColor=black" />
    </a>
    <a href="https://www.erlang.org/" alt="Supported Erlang version">
        <img src="https://img.shields.io/badge/Erlang-27-green.svg" />
    </a>
    <a href="LICENSE" alt="License">
        <img src="https://img.shields.io/github/license/openworkload/swm-core" />
    </a>
    <a href="CODE_OF_CONDUCT.md" alt="Contributor Covenant">
        <img src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg" />
    </a>
    <a href="https://github.com/openworkload/swm-core/actions/workflows/ci.yml" alt="Latest CI tests result">
        <img src="https://github.com/openworkload/swm-core/actions/workflows/ci.yml/badge.svg?event=push" />
    </a>
</p>

Sky Port
========


## Introduction

[This](https://github.com/openworkload/swm-core) is a core component of the Sky Port project. It is an universal bus between user software and compute resources. In other words this is a transportation layer between workload producers and compute resource providers. Sky Port makes it easy to connect user software to different cloud resources.


## Design

Terminology:

* Remote Site: remote computing system where user jobs run. It can be either cloud or on-premises cluster (depending on the connected gate).
* swm (Sky Port Workload Manager): a core service of Sky Port that runs in a background on the user’s desktop and performs all required operations on remote sites.
* Terminal: user software that connects to swm, submits jobs, retrieves current jobs status, displays the information. From user prospective the terminal is an interface to remote sites where jobs run. The user should not care that the terminal connects to swm and not to the remote sites directly.
* Gate: a plugin for swm that is in charge of all communications with one particular remote site.


Sky Port consists of 3 main components:
   * [Core](https://github.com/openworkload/swm-core) (this repository).
   * Gate. See the [default cloud gate](https://github.com/openworkload/swm-cloud-gate) as a gate example.
   * Terminal. See the [JupyterLab terminal](https://github.com/openworkload/swm-jupyter-term) as a terminal example.

The idea here is the following: APIs of the Core and the Gate are predefined. Thus each of the components can be replaced to more suitable for the user problem ones. The core component code is located in the current repository and can be considered as a reference and a prove of concept. The project is started recently and requires some time for API stabilization. Thus one can consider this code for now as highly experimental.

See also [openworkload.org](https://openworkload.org) 


## How to run

### Prepare credentials.json

See [AZURE.md](HOWTO/AZURE.md) for details.

### Pull skyport container
```bash
docker pull openworkload/skyport:latest
```

### Start skyport container (as a regular user)
```bash
DOMAIN=openworkload.org
FQDN=$(hostname).$DOMAIN
docker network create skyportnet
docker run -v $HOME/.ssh:$HOME/.ssh -v $HOME/.swm:$HOME/.swm -v $HOME/.cache/swm:/root/.cache/swm --name skyport --network skyportnet --network-alias $FQDN -h $FQDN --domainname $DOMAIN -ti -e SKYPORT_USER=$(id -u -n) -e SKYPORT_USER_ID=$(id -u) openworkload/skyport
```
On first run the container creates a configuration in $HOME/.swm/spool (generates sertificates, creates swm-core configuration, etc) and exits.
After the exit the user needs to ensure that Azure cloud provider is configured correctly:
* Service principal is created.
* Newly generated skyport user public certificate a loaded to the service principal application.
* Optionally container registry is configured and container images are uploaded there.
See details [here](HOWTO/AZURE.md)

When the cloud provider account is configured then run skyport container again:
```bash
docker start skyport
```
The procedure of building a new skyport container from scratch is described [here](HOWTO/BUILD.md).


## Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so without any further discussion. If you plan to contribute new features, utility functions or extensions, please first open an issue and discuss the feature with us. Our code of conduct can be found [here](CODE_OF_CONDUCT.md).


## License

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license. See the [LICENSE](LICENSE) file for details.
