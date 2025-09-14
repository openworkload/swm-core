.PHONY: all gen porter compile release
.PHONY: run-ghead run-chead
.PHONY: test ftest
.PHONY: cb cr
.PHONY: dialyzer format static_checks

COG = cog
REBAR = ./rebar3
BUILD_DEBUG_CONTAINER = scripts/build-debug-container.sh
START_DEBUG_CONTAINER = scripts/start-debug-container.sh
BUILD_RELEASE_CONTAINER = scripts/build-release-container.sh
START_RELEASE_CONTAINER = scripts/start-release-container.sh

VERSION = $(shell scripts/version)

HELP_FUN = \
    %help; \
    while(<>) { push @{$$help{$$2 // 'COMMON'}}, [$$1, $$3]\
    if /^([a-zA-Z\-]+)\s*:.*\#\#(?:@([a-zA-Z\-]+))?\s(.*)$$/ }; \
    print "USAGE:\n  make [target]\n\n"; \
    print "\n";\
    for (sort keys %help) { \
    print "${WHITE}$$_:${RESET}\n"; \
    for (@{$$help{$$_}}) { \
    $$sep = " " x (16 - length $$_->[0]); \
    print "  ${YELLOW}$$_->[0]${RESET}$$sep${GREEN}$$_->[1]${RESET}\n"; \
    }; \
    print "\n"; }

export REBAR_CACHE_DIR=${HOME}/.cache/rebar3

all: gen compile porter format

help:		## Show this help
			@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

build-debug-container:			##@CONTAINERS build development container image
			$(BUILD_DEBUG_CONTAINER)

build-release-container:			##@CONTAINERS build release container image
			$(BUILD_RELEASE_CONTAINER)

start-release-container:			##@CONTAINERS start release container
			$(START_RELEASE_CONTAINER)

shell-release-container:			##@CONTAINERS run shell in already running release container
			docker exec -ti skyport /bin/bash

cr: 		##@CONTAINERS run or attach to running container
			$(START_DEBUG_CONTAINER)

gen:		##@SKYPORT Generate entity files
			$(COG) -U -z -d -e -c -o ./src/lib/wm_entity.hrl ./src/lib/wm_entity.hrl.cog
			$(COG) -U -z -d -e -c -o ./src/lib/wm_entity.erl ./src/lib/wm_entity.erl.cog
			scripts/autogen-cpp.py

porter:		##@SKYPORT Compile Porter
			$(MAKE) -C c_src/porter

compile:	##@SKYPORT Compile Core
			$(REBAR) compile

release:	##@SKYPORT Build release tar.gz package
			rm -fr ./_build/default/rel/swm
			$(REBAR) release
			# relx can't copy files from directory by wildcard, but it can copy full directory
			# like {copy, "priv/", "priv/"}, but result will be priv/priv, workaround for that
			# will be {copy, "priv/", "./"}, but it's blow minds rebar3->relx->erl_tar, which
			# keep result archive tar.gz file in the same directory as archived files, as result
			# erl_tar continuously add archive tar.gz file to himself. So, code below it's just
			# temporary workaround.
			cp -rf priv _build/default/rel/swm/
			sed -i'' 's/SWM_VERSION=.*/SWM_VERSION=$(VERSION)/' _build/default/rel/swm/scripts/swm.env
			mkdir -p _build/packages
			rm -f _build/packages/swm-$(VERSION).tar.gz
			tar --transform 's,^\.,$(VERSION),' -czf _build/packages/swm-$(VERSION).tar.gz -C _build/default/rel/swm .

run-ghead: gen compile porter	##@RUN Run grid head node (1st hier level)
			scripts/run-in-shell.sh -g

run-chead: gen compile porter	##@RUN Run cluster head node (2nd hier level)
			scripts/run-in-shell.sh -c

run-skyport:	##@RUN Run Sky Port core in foreground
			scripts/run-in-shell.sh -x

test:		##@TESTS Run unit and functional erlang tests
			scripts/swm.env
			$(REBAR) eunit skip_deps=true
			$(REBAR) ct -v

test_unit:		##@TESTS Run unit erlang tests
			$(REBAR) eunit skip_deps=true

test_ct:		##@TESTS Run common erlang tests
			$(REBAR) ct --dir test --verbose

ftest:		##@TESTS Run functional tests
			scripts/swm.env
			test/test-all.sh

clean:		##@DEV Clean sources
			$(REBAR) clean
			rm -f erl_crash.dump
			$(MAKE) clean -C c_src/porter
			$(MAKE) clean -C c_src/lib

dialyzer:		##@DEV Run dialyzer
			$(REBAR) dialyzer

format:		##@DEV Format erlang code
			$(REBAR) format

static_checks:		##@DEV Run erlang static checks to validate the code
			$(REBAR) lint
			$(REBAR) hunk

tmux:	##@DEV Run tmux with Sky Port development layout
	SOURCES_PARENT_DIR=~/projects tmuxinator

update_rebar:
	$(REBAR) local upgrade
	$(REBAR) plugins upgrade --all

unlock_rebar:
	$(REBAR) unlock -a

update_deps:
	$(REBAR) update-deps

upgrade_deps:
	$(REBAR) upgrade -a

worker: release
	scripts/update-worker.sh --dev-mode
