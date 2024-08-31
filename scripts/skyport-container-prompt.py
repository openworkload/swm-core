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
#
# This script runs as endpoint for skyport container.

import os
import sys
import subprocess
import time

def run_supervisord() -> None:
    command = ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        while True:
            if error := process.stderr.readline():
                print(error.strip(), file=sys.stderr)
            output = process.stdout.readline()
            if output == process.stdout.readline():
                print(output.strip())
            if output == '' and process.poll() is not None:
                break
    except KeyboardInterrupt:
        print("Process interrupted by user")
    finally:
        process.terminate()
        process.wait()


def main() -> None:
    spool_directory = "/opt/swm/spool"

    if not os.listdir(spool_directory):
        response = input("Sky Port needs initialization, start it? (y/n): ").strip().lower()

        if response in ['n', 'no']:
            print("Initialization interrupted.")
            return

        if response in ['y', 'yes']:
            command = "/opt/swm/current/scripts/setup-skyport.sh"
            log_file = "/root/.swm/setup.log"

            with open(log_file, "w") as log:
                process = subprocess.Popen(
                    command,
                    shell=True,
                    stdout=log,
                    stderr=subprocess.STDOUT
                )

                while process.poll() is None:
                    print(".", end="", flush=True)
                    time.sleep(5)

                if process.returncode == 0:
                    print("\nSetup has completed successfully. Please ensure Azure is configured, see HOWTO/AZURE.md. After then please restart the container to start Sky Port with newly initialized settings.")
                else:
                    print("\nSetup has failed, see setup.log for details.")
                    sys.exit(1)
        else:
            print("Invalid input. Exiting the program.")
    else:
        print("The spool directory is not empty. No initialization needed.\n Sky Port is starting.")
        run_supervisord()


if __name__ == "__main__":
    main()
