#!/usr/bin/env python3
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

import os
import json
import subprocess
import collections


def run(cmd):
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
    output = proc.stdout.read()
    print(output.decode("utf8"), end="")


def main():
    json_data = open("./priv/schema.json")
    data = json.load(json_data, object_pairs_hook=collections.OrderedDict)

    exclude = {"malfunction", "table", "service", "subscriber", "test"}

    lib_path = "./c_src/lib"
    h_cog_file = os.path.join(lib_path, "wm_entity.h.cog")
    c_cog_file = os.path.join(lib_path, "wm_entity.cpp.cog")

    for entity in data:
        if entity in exclude:
            continue
        cmd = "cog -U -z -d -e -c -D WM_ENTITY_NAME=%s" % entity
        h_out_file = os.path.join(lib_path, "wm_%s.h" % entity)
        c_out_file = os.path.join(lib_path, "wm_%s.cpp" % entity)
        run("%s -o %s %s" % (cmd, h_out_file, h_cog_file))
        run("%s -o %s %s" % (cmd, c_out_file, c_cog_file))


if __name__ == "__main__":
    main()
