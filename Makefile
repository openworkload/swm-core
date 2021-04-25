.PHONY: all gen porter compile release
.PHONY: run-ghead run-chead
.PHONY: test ftest
.PHONY: cb cr
.PHONY: dialyzer format

COG = cog.py
REBAR = ./rebar3
BUILD_CONTAINER = scripts/build-dev-container.sh
START_CONTAINER = scripts/start-dev-container.sh

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


all: gen compile porter

help:		## Show this help
			@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

cb:			##@CONTAINERS build container image
			$(BUILD_CONTAINER)

cr: 		##@CONTAINERS run or attach to running container
			$(START_CONTAINER)

gen:		##@SWM Generate files for SWM and Porter
			$(COG) -U -z -d -e -c -o ./src/lib/wm_entity.hrl ./src/lib/wm_entity.hrl.cog
			$(COG) -U -z -d -e -c -o ./src/lib/wm_entity.erl ./src/lib/wm_entity.erl.cog
			scripts/autogen-cpp.py

porter:		##@SWM Compile Porter
			$(MAKE) -C c_src/porter

compile:	##@SWM Compile SWM
			$(REBAR) compile

release:	##@SWM Build release tar.gz package
			$(REBAR) release
			# relx can't copy files from directory by wildcard, but it can copy full directory
			# like {copy, "priv/", "priv/"}, but result will be priv/priv, workaround for that
			# will be {copy, "priv/", "./"}, but it's blow minds rebar3->relx->erl_tar, which
			# keep result archive tar.gz file in the same directory as archived files, as result
			# erl_tar continuously add archive tar.gz file to himself. So, code below it's just
			# temporary workaround.
			cp -rf priv _build/default/rel/swm/
			sed -i'' 's/SWM_VERSION=.*/SWM_VERSION=$(VERSION)/' _build/default/rel/swm/scripts/swm.env
			cd  _build/default/rel/swm && rm -f swm-$(VERSION).tar.gz; tar --transform 's,^\.,$(VERSION),' -czf swm-$(VERSION).tar.gz ./*

run-ghead: gen compile porter	##@RUN Run grid head node (1st hier level)
			scripts/run-in-shell.sh -g

run-chead: gen compile porter	##@RUN Run cluster head node (2nd hier level)
			scripts/run-in-shell.sh -c

test:		##@TESTS Run unit and functional erlang tests
			scripts/swm.env
			$(REBAR) eunit skip_deps=true
			$(REBAR) ct -v

test_unit:		##@TESTS Run unit erlang tests
			scripts/swm.env
			$(REBAR) eunit skip_deps=true

test_ct:		##@TESTS Run common erlang tests
			$(REBAR) ct --dir test

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
