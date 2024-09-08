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
import time
import pwd
import shutil
import subprocess


def get_username() -> str:
    if username := os.environ.get("SKYPORT_USER"):
        print(f"Username from environment: {username}")
        return username
    while True:
        if username := input("Enter container user name: ").strip().lower():
            return username


def render_supervisor_config(username: str) -> None:
    template_path = "/etc/supervisor/supervisord.conf.template"
    output_path = "/etc/supervisor/conf.d/supervisord.conf"

    if os.path.exists(output_path):
        print(f"Supervisord configuration file exists: {output_path}")
        return

    with open(template_path, "r") as template_file:
        template_content = template_file.read()

    rendered_content = template_content.replace("{{ USERNAME }}", username)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as output_file:
        output_file.write(rendered_content)

    print(f"Supervisord configuration file rendered: {output_path}")


def run_supervisord(username: str = "") -> None:
    if username:
        render_supervisor_config(username)
    command = ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-l", "/tmp/supervisord.log"]
    print(f"Start supervisord for Sky Port daemons:\n  {' '.join(command)}")
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


def add_system_user(username: str) -> None:
    uid = os.environ.get("SKYPORT_USER_ID")
    if uid:
        print(f"UID from environment: {uid}")
    else:
        uid = input("Enter container user system id: ").strip().lower()
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


def ensure_symlinks(home: str) -> None:
    src_path = f"{home}/.swm/spool"
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
    command = f"/opt/swm/current/scripts/setup-skyport.sh -u {username}"
    log_file = "/var/log/setup-skyport.log"

    print(f"Running command: {command}")
    with open(log_file, "w") as log_file:
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )

        process.wait()
        if process.returncode == 0:
            print("\n"
                  "Sky Port has been initialized.\n"
                  "Please ensure now that Azure is configured, see HOWTO/AZURE.md.\n"
                  "The container will be stopped now. Start again when Azure is ready.\n"
                  )
        else:
            print(f"Setup has failed with exit code {process.returncode}.\n"
                  "See /var/log/setup-skyport.log for details.")
            sys.exit(1)


def ask_clean_spool(spool_directory: str) -> None:
    while True:
        if not os.path.exists(spool_directory):
            break
        if os.listdir(spool_directory):
            answer = input(f"Recreate configuration located in {spool_directory}? [N] ").strip().lower()
            if answer in ["yes", "y"]:
                shutil.rmtree(spool_directory)
                break
            elif answer in ["no", "n"] or not answer:
                break
        else:
            break


def get_user_home(username: str) -> str:
    try:
        user_info = pwd.getpwnam(username)
        return user_info.pw_dir
    except KeyError:
        pass
    return f"/home/{username}"


def touch(file_path: str) -> None:
    with open(file_path, 'w') as file:
        pass


def main() -> None:
    username = get_username()
    if not username:
        print("User name is unknown")
        sys.exit(1)

    skyport_initialized_file = "/skyport-initialized"
    if os.path.exists(skyport_initialized_file):
        run_supervisord(username)

    home = get_user_home(username)
    if not home:
        print("User home is unknown")
        sys.exit(1)

    spool_directory = f"{home}/.swm/spool"
    ask_clean_spool(spool_directory)

    if not os.path.exists(spool_directory):
        os.makedirs(spool_directory)

    if not os.path.exists(spool_directory) or not os.listdir(spool_directory):
        print(f"Spool directory is not initialized: {spool_directory}")
        add_system_user(username)
        ensure_symlinks(home)
        setup_skyport(username)
    else:
        run_supervisord(username)

    touch(skyport_initialized_file)


if __name__ == "__main__":
    main()
