#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

## Export variables
source ${ROOT_DIR}/scripts/swm.env


SWMCTL=${ROOT_DIR}/scripts/swmctl

function start_ghead() {
  erl -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_sasl -detached \
    -s swm -eval "dbg:tracer()." -eval "dbg:p(all, c)." -eval "dbg:tpl(wm_data, [])." -s swm
}

function start_sim_nodes() {
  cd ..
  $SWMCTL node startsim chead1
  sleep 1
  $SWMCTL node startsim phead1
  sleep 1
  $SWMCTL node startsim node001
  $SWMCTL node startsim node002
  $SWMCTL node startsim node003
}

start_ghead
sleep 1
start_sim_nodes

