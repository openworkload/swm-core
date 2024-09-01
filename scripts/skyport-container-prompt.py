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
# This script runs as an endpoint for skyport container.

import os
import sys
import subprocess
import time


def run_supervisord() -> None:
    command = ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-l", "/tmp/supervisord.log"]
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


def add_user() -> None:
    username = input("Enter admin user name (will be VM admin): ").strip().lower()
    uid = input("Enter admin user system UID: ").strip().lower()
    try:
        subprocess.run([
                        "useradd",
                        "--uid", uid,
                        "--no-create-home",
                        username,
                       ],
                       check=True)
        print(f"User '{username}' created successfully with UID={uid}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating user '{username}': {e}")
        sys.exit(1)
    return username


def ensure_symlinks(username: str) -> None:
    src_path = f"/home/{username}/.swm/spool"
    dst_path = "/opt/swm/spool"
    os.makedirs(src_path, exist_ok=True)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    try:
        os.symlink(src_path, dst_path)
        print(f"Symlink created: {dst_path} -> {src_path}")
    except FileExistsError:
        print(f"Symlink already exists: {dst_path}")
    except OSError as e:
        print(f"Error creating symlink: {e}")


def setup_skyport(username: str) -> None:
    #command = ["/opt/swm/current/scripts/setup-skyport.sh", "-u", username]
    command = "/opt/swm/current/scripts/setup-skyport.sh -u" + username
    log_file = "/var/log/setup-skyport.log"

    #print(f"Running command: {' '.join(command)}")
    print(f"Running command: {command}")
    with open(log_file, "w") as log:
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=log,
            stderr=subprocess.STDOUT
        )

        while process.poll() is None:
            print(".", end="", flush=True)
            time.sleep(1)

        if process.returncode == 0:
            print("\n\n"
                  "Setup has completed successfully.\n"
                  "Ensure Azure is configured, see HOWTO/AZURE.md.\n"
                  "Then restart the container to start Sky Port.\n")
        else:
            print(f"Setup has failed with exit code {process.returncode},\n"
                  "see /var/log/setup-skyport.log for details.")
            sys.exit(1)


def main() -> None:
    spool_directory = "/opt/swm/spool"

    if not os.path.exists(spool_directory) or not os.listdir(spool_directory):
        response = None
        while (not response):
            response = input("Sky Port needs initialization, start it? (y/n): ").strip().lower()
            if response in ['n', 'no']:
                print("Initialization interrupted.")
                return
            if response in ['y', 'yes']:
                if username := add_user():
                    ensure_symlinks(username)
                    setup_skyport(username)
                else:
                    print("Username is unknown")
                    sys.exit(1)
            else:
                print("Type Y or N")
                response = None
    else:
        print("No initialization needed. Sky Port is starting.")
        import time
        time.sleep(100000)
        run_supervisord()


if __name__ == "__main__":
    main()
