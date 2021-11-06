The python client interface for Sky Workload Manager core daemon API
====================================================================

# Description

Sky Port is an universal bus between user software and compute resources.
It can also be considered as a transportation layer between workload producers
and compute resource providers. Sky Port makes it easy to connect user software
to different cloud resources.

The current python package represents a wrapper around client REST API of the core
component of Sky Port -- [core daemon](https://github.com/skyworkflows/swm-core).
The package provides classes and data structures that can be used in python programs 
in order to communicate with swm-core. Such communication is useful when Sky Port
terminals are built (see [JupyterLab terminal](https://github.com/skyworkflows/swm-jupyter-term)
as an example).

# Build

## Requirements:
    sudo apt-get install python3-all-dev
    sudo apt install python3-pip


## Run unit tests
    make test


## Build pip package

### Requirements:
    sudo python3 -m pip install --upgrade pip setuptools wheel
    sudo python3 -m pip install tqdm
    sudo python3 -m pip install --user --upgrade twine

### Build the package:
    make clean
    make package

### Upload to pypi.org:
    make upload


# Setup

## Installation:
    python3 -m pip install --user swmclient

## Uninstallation:
    python3 -m pip uninstall swmclient


# Contributing

We appreciate all contributions. If you are planning to contribute back bug-fixes, please do so
without any further discussion. If you plan to contribute new features, utility functions or extensions,
please first open an issue and discuss the feature with us.

# Lincese

We use a shared copyright model that enables all contributors to maintain the copyright on their contributions.

This software is licensed under the BSD-3-Clause license.
