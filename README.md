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

Sky Port makes it easy to consume cloud resources by user software.

[This repository](https://github.com/openworkload/swm-core) contains sources of the workload manager (core component of the Sky Port project). It supports a full workload lifecicle in cloud:
  * job submission,
  * job scheduling,
  * cloud cluster creation,
  * ports forwarding,
  * job data uploading,
  * job container pulling and starting
  * job monitoring,
  * job results and logs downloading,
  * the cloud resources removal.


## Design

Terminology:

  * **Remote Site**: remote computing system where user jobs run. Currently it is Microsoft Azure.
  * **swm** (Sky Port Workload Manager): a core service (daemon) of Sky Port that orchestrate the workload.
  * **Terminal**: any user software that connects to swm-core, submits jobs, retrieves current jobs status, displays the information. From user prospective the terminal is an interface to remote sites where jobs run. It uses swm-core as a transportanion layer to run its workload.
  * **Gate**: a service that is used by swm-core, and which is in charge of all communications with one or several remote site.


Sky Port consists of 3 main components:
  * **[Core](https://github.com/openworkload/swm-core)** (this repository).
  * **Gate*. See the [default cloud gate](https://github.com/openworkload/swm-cloud-gate) as a gate example.
  * **Terminal**. See the [JupyterLab terminal](https://github.com/openworkload/swm-jupyter-term) as a terminal example.

See [openworkload.org](https://openworkload.org) for details 


## How to run

### Pull skyport container
```bash
docker pull openworkload/skyport:latest
```

### Start skyport container (as a regular user)

```bash
make start-release-container
```

This command starts Sky Port container with swm-core and cloud gate processes inside. If spool directory ($HOME/.swm/spool/) is missed or empty, then the container spawns the prompt script that asks a few questions. The script then bootstraps the spool directory with new certificates and swm-core configuration. After that the container stops. If spool already ready then the container just starts swm-core and the gate in background.

If the spool is created and the container is stopped then the user needs to ensure that Azure cloud provider is configured correctly, see [AZURE.md](https://github.com/openworkload/swm-cloud-gate/blob/master/HOWTO/AZURE.md). When the configuration is completed, then run skyport container again:
```bash
docker start skyport
```
This command starts swm-core and gate in background if the spool is (still) ready.

If you prefer to build Sky Port container image from scratch, then [this instructions can be used](HOWTO/BUILD.md).


## Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so without any further discussion. If you plan to contribute new features, utility functions or extensions, please first open an issue and discuss the feature with us. Our code of conduct can be found [here](CODE_OF_CONDUCT.md).


## License

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license. See the [LICENSE](LICENSE) file for details.
