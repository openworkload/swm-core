## Introduction

[This](https://github.com/skyworkflows/swm-core) is a core component of the Sky Port (SP) project. SP is an universal bus between user software and compute resources. This can be considered as a transportation layer between workload producers and compute resource providers. Sky Port makes it easy to connect user software to different cloud resources.

## Design

Terminology:

* Sky Workload Manager: predecessor of SP. It was designed to controle a large number of HPC clusters and was smoothly transformed to SP.
* Remote Site: remote computing system where user jobs run. It can be either cloud or on-premise cluster (depending on the connected gate).
* swm: service that runs in a background on the user’s desktop and performs all required operations on remote sites.
* Terminal: user software that can connect to swm, submits jobs, retrieves current jobs status, displays the information. For the user the terminal is an interface to remote sites where his jobs run. The user should not really care that the terminal connects to swm, not to the remote sites directly.
* Gate: a plugin for swm that is in charge of all communications with one particular remote site.


SP consists of 3 main components:
   * [Core](https://github.com/skyworkflows/swm-core) (this repository).
   * Gate. See the [default cloud gate](https://github.com/skyworkflows/swm-cloud-gate).
   * Terminal. See the [JupyterLab terminal](https://github.com/skyworkflows/swm-jupyter-term).

The idea here is the following: API of all of those 3 components are well described. Thus the components can be replaced to more suitable for the user problem ones. The core component in the current repository is developed as a reference for other core components. The project is started recently and require time to stabilize the components API. Thus one can consider this code as highly experimental for now.

## Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so without any further discussion. If you plan to contribute new features, utility functions or extensions, please first open an issue and discuss the feature with us.

## License

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license. See the [LICENSE](LICENSE) file for details.

