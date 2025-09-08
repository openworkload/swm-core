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
#
""" Helper functions and data for C++ and Erlang files generation.
"""

exclude = {"malfunction", "table", "service", "subscriber", "test"}

types_map = {
    "atom()": "std::string",
    "any()": "char*",
    "map()": "std::map<std::string, std::string>",
    "string()": "std::string",
    "binary()": "char*",
    "integer()": "int64_t",
    "pos_integer()": "uint64_t",
    "float()": "double",
    ## USER DEFINED TYPES
    "remote_id()": "std::string",
    "account_id()": "std::string",
    "session_id()": "std::string",
    "user_id()": "std::string",
    "grid_id()": "std::string",
    "cluster_id()": "std::string",
    "partition_id()": "std::string",
    "node_id()": "std::string",
    "job_id()": "std::string",
    "image_id()": "std::string",
    "relocation_id()": "std::uint64_t",
    "hook_id()": "std::string",
}

type_suffix_map = {
    "atom()": "atom",
    "any()": "buff",
    "map()": "map",
    "string()": "str",
    "binary()": "buff",
    "integer()": "int64_t",
    "pos_integer()": "uint64_t",
    "float()": "double",
    ## USER DEFINED TYPES SUFFIX
    "remote_id()": "str",
    "account_id()": "str",
    "session_id()": "str",
    "user_id()": "str",
    "grid_id()": "str",
    "cluster_id()": "str",
    "partition_id()": "str",
    "node_id()": "str",
    "job_id()": "str",
    "image_id()": "str",
    "relocation_id()": "uint64_t",
    "hook_id()": "str",
}

printer = {
    "atom()": "%s",
    "any()": "buff",
    "map()": "buff",
    "binary()": "buff",
    "string()": "%s",
    "integer()": "%ld",
    "pos_integer()": "%ld",
    "float()": "%f",
    ## USER DEFINED PRINTERS
    "remote_id()": "%s",
    "account_id()": "%s",
    "session_id()": "%s",
    "user_id()": "%s",
    "grid_id()": "%s",
    "cluster_id()": "%s",
    "partition_id()": "%s",
    "node_id()": "%s",
    "job_id()": "%s",
    "image_id()": "%s",
    "relocation_id()": "%ld",
    "hook_id()": "%s",
}


def struct_param_type(r):
    is_tuple = False
    if "#" in r:
        if r.startswith("#"):
            r = r[1:]
        r = r.replace("{}", "")
        is_tuple = True
    return ("Swm" + r.title(), r, is_tuple)


def get_tuple_type(pp):
    tuple_type = ""
    for tp in pp:
        tp = tp.strip()
        if tp == "atom()":
            tuple_type += "_atom"
        elif tp == "string()":
            tuple_type += "_str"
        elif tp == "any()":
            tuple_type += "_buff"
    return tuple_type


def c_struct(pp):
    s = "SwmTuple"
    for p in pp:
        p = p.strip()
        if p in type_suffix_map.keys():
            p = type_suffix_map[p]
        if len(p) > 1:
            s += p.title()
    return s
