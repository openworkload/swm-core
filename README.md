## Introduction

[This](https://github.com/skyworkflows/swm-core) is a core component of the Sky Port (SP) project. SP is an universal bus between user software and compute resources. It can also be considered as a transportation layer between workload producers and compute resource providers. Sky Port makes it easy to connect user software to different cloud resources.

## Design

Terminology:

* Sky Workload Manager: predecessor of SP. It was designed to control a large number of HPC clusters and was smoothly transformed to SP.
* Remote Site: remote computing system where user's jobs run. It can be either cloud or on-premises cluster (depending on the connected gate).
* swm: service that runs in a background on the user’s desktop and performs all required operations on remote sites.
* Terminal: user software that can connect to swm, submits jobs, retrieves current jobs status, displays the information. For the user the terminal is an interface to remote sites where his jobs run. The user should not really care that the terminal connects to swm and not to the remote sites directly.
* Gate: a plugin for swm that is in charge of all communications with one particular remote site.


SP consists of 3 main components:
   * [Core](https://github.com/skyworkflows/swm-core) (this repository).
   * Gate. See the [default cloud gate](https://github.com/skyworkflows/swm-cloud-gate) as a gate example.
   * Terminal. See the [JupyterLab terminal](https://github.com/skyworkflows/swm-jupyter-term) as a terminal example.

The idea here is the following: API of the Core and the Gate is well described. Thus each of the components can be replaced to more suitable for the user problem ones. The core component code is located in the current repository and can be considered as a reference and a prove of concept. The project is started recently and requires some time for stabilization of the API. Thus one can consider this code for now as highly experimental.

## How to run

User can pull or build docker container that will run the Core. The procedure of building and running swm-core container is [described here](https://github.com/skyworkflows/swm-core/blob/master/priv/prod/README.md) 


## Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so without any further discussion. If you plan to contribute new features, utility functions or extensions, please first open an issue and discuss the feature with us.

## License

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license. See the [LICENSE](LICENSE) file for details.

