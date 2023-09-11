Sky Port
========


## Introduction

[This](https://github.com/openworkload/swm-core) is a core component of the Sky Port (SP) project. SP is an universal bus between user software and compute resources. In other words this is a transportation layer between workload producers and compute resource providers. Sky Port makes it easy to connect user software to different cloud resources.


## Design

Terminology:

* Remote Site: remote computing system where user jobs run. It can be either cloud or on-premises cluster (depending on the connected gate).
* swm (Sky Port Workload Manager): a core service of Sky Port that runs in a background on the user’s desktop and performs all required operations on remote sites.
* Terminal: user software that connects to swm, submits jobs, retrieves current jobs status, displays the information. From user prospective the terminal is an interface to remote sites where jobs run. The user should not care that the terminal connects to swm and not to the remote sites directly.
* Gate: a plugin for swm that is in charge of all communications with one particular remote site.


SP consists of 3 main components:
   * [Core](https://github.com/openworkload/swm-core) (this repository).
   * Gate. See the [default cloud gate](https://github.com/openworkload/swm-cloud-gate) as a gate example.
   * Terminal. See the [JupyterLab terminal](https://github.com/openworkload/swm-jupyter-term) as a terminal example.

The idea here is the following: APIs of the Core and the Gate are predefined. Thus each of the components can be replaced to more suitable for the user problem ones. The core component code is located in the current repository and can be considered as a reference and a prove of concept. The project is started recently and requires some time for API stabilization. Thus one can consider this code for now as highly experimental.

See also [openworkload.org](https://openworkload.org) 

## How to run

Pull or build a container that will run the Core. The procedure of building and running swm-core container is [described here](https://github.com/openworkload/swm-core/blob/master/priv/prod/README.md) 


## Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so without any further discussion. If you plan to contribute new features, utility functions or extensions, please first open an issue and discuss the feature with us.


## License

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license. See the [LICENSE](LICENSE) file for details.
