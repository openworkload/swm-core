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

import argparse
import os
import pwd
import shutil
import subprocess
import sys
import threading
import time

DEV_MODE: bool = False


def get_location(default: str = "eastus2") -> str:
    if location := os.environ.get("SKYPORT_REMOTE_LOCATION"):
        print(f"Location from SKYPORT_REMOTE_LOCATION environment: {location}")
        return location
    if location := input(f"Enter remote location [{default}]: ").strip().lower():
        return location
    else:
        return default


def get_username() -> str:
    if username := os.environ.get("SKYPORT_USER"):
        print(f"Username from SKYPORT_USER environment: {username}")
        return username
    if username := os.environ.get("USER"):
        print(f"Username from USER environment: {username}")
        return username
    while True:
        if username := input("Enter container user name: ").strip().lower():
            return username


def render_supervisor_config(username: str) -> None:
    if DEV_MODE:
        output_path = "/tmp/supervisord.conf"
        template_path = "./priv/container/debug/supervisord.conf"
    else:
        output_path = "/etc/supervisor/conf.d/supervisord.conf"
        template_path = "/etc/supervisor/supervisord.conf.template"
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


def render_supervisor_gate_config(username: str) -> None:
    if DEV_MODE:
        output_path = "/tmp/supervisord_gate.conf"
        template_path="./priv/container/debug/supervisord_gate.conf"
    else:
        output_path = "/etc/supervisor/conf.d/supervisord_gate.conf"
        template_path = "/etc/supervisor/supervisord_gate.conf.template"
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


def warm_up_cache(username: str, home: str) -> bool:
    cache_dir = "/opt/swm/spool/cache/"
    print(f"Try to warm the gate cache up: {cache_dir}")
    if os.path.exists(cache_dir) and os.listdir(cache_dir):
        print(f"Directory {cache_dir} is not empty (no cache update is required)")
        return True

    process_supervisor = run_supervisord(username, pipe=False, gate_only=True)
    if not process_supervisor:
        print("Cannot start supervisor")
        return False
    time.sleep(5)

    if DEV_MODE:
        script = "../swm-cloud-gate/swmcloudgate/update-azure-caches.py"
    else:
        script = (
            "/usr/local/lib/python/site-packages/swmcloudgate/update-azure-caches.py"
        )

    result: Dict[str, int] = {}

    env = os.environ
    env["SWM_CLOUD_CREDENTIALS_FILE"] = f"{home}/.swm/credentials.json"
    env["SWM_SPOOL"] =  "/opt/swm/spool" if username == "root" else f"{home}/.swm/spool"

    def run_cache_update_scripts():
        print(f"Run gate cache update script: {script}")
        try:
            process = subprocess.Popen(["python3", script], env=env)
            print("Gate cache update script process started")
            process.wait()
            result["exit_code"] = process.returncode
        except Exception as e:
            result["exit_code"] = -1
            print(f"Gate script {script} failed: {e}")

    script_thread = threading.Thread(target=run_cache_update_scripts)
    print("Start cache update script thread")
    script_thread.start()

    while script_thread.is_alive():
        time.sleep(5)
        print(".", end="", flush=True)

    script_thread.join()

    process_supervisor.terminate()
    exit_code = result.get("exit_code", -1)
    print(f"\nGate cache update script exit code: {exit_code}")
    return exit_code == 0


def ensure_worker_exists() -> bool:
    if DEV_MODE:
        return
    script_dir = os.path.abspath(os.path.dirname(__file__))
    command = f"{script_dir}/update-worker.sh"
    print(f"Update worker archive with command: {command}")
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        while True:
            if error := process.stderr.readline():
                if msg := error.strip():
                    print(msg, file=sys.stderr)
            output = process.stdout.readline()
            if output == process.stdout.readline():
                if msg := output.strip():
                    print(msg)
            if output == "" and process.poll() is not None:
                break
    except KeyboardInterrupt:
        print("Process interrupted by user")
        return False
    except Exception as e:
        print(f"Failed to update worker archive: {e}")
        return False
    finally:
        process.terminate()
        process.wait()
    return True


def run_supervisord(
    username: str, pipe: bool = True, gate_only: bool = False
) -> subprocess.Popen:
    if username:
        render_supervisor_config(username)
        render_supervisor_gate_config(username)
    sup_dir = "/tmp" if DEV_MODE else "/etc/supervisor/conf.d"
    sup_conf = f"{sup_dir}/supervisord{'_gate' if gate_only else ''}.conf"
    command = ["supervisord", "-c", sup_conf, "-l", "/tmp/supervisord.log"]
    if pipe:
        command += ["--nodaemon"]
    print(f"Start supervisord:\n  {' '.join(command)}")
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE if pipe else subprocess.DEVNULL,
            stderr=subprocess.PIPE if pipe else subprocess.DEVNULL,
            text=True,
        )
        while True:
            if not pipe:
                break
            if error := process.stderr.readline():
                print(error.strip(), file=sys.stderr)
            output = process.stdout.readline()
            if output == process.stdout.readline():
                print(output.strip())
            if output == "" and process.poll() is not None:
                break
        return process
    except KeyboardInterrupt:
        print("Process interrupted by user")
    except Exception as e:
        print(f"Failed to start '{command}': {e}")
        return None
    finally:
        if pipe:
            process.terminate()
            process.wait()


def user_exists(username: str) -> bool:
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False


def ensure_system_user_exists(username: str) -> None:
    uid = os.environ.get("SKYPORT_USER_ID")
    if uid:
        print(f"UID from environment: {uid}")
    else:
        uid = input("Enter container user system id: ").strip().lower()
    if DEV_MODE:
        print(f"SKIP adding system user in dev mode with UID={uid}")
        return
    if user_exists(username):
        print(f"User {username} already exists")
        return
    try:
        subprocess.run(
            [
                "useradd",
                "--uid",
                uid,
                "--no-create-home",
                username,
            ],
            check=True,
        )
        print(f"User '{username}' created successfully with UID={uid}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating user '{username}': {e}")
        sys.exit(1)


def ensure_symlinks(home: str) -> None:
    src_path = f"{home}/.swm/spool"
    dst_path = "/opt/swm/spool"
    if DEV_MODE:
        print(f"SKIP creation of symlink in dev mode: {src_path} -> {dst_path}")
        return
    os.makedirs(src_path, exist_ok=True)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    try:
        os.symlink(src_path, dst_path)
        print(f"Symlink created: {dst_path} -> {src_path}")
    except FileExistsError:
        print(f"Symlink already exists: {dst_path}")
    except OSError as e:
        print(f"Error creating symlink: {e}")


def setup_skyport(username: str, location: str) -> None:
    if DEV_MODE:
        log_file = "/tmp/setup-skyport.log"
        command = f"./scripts/setup-skyport-dev.sh -u {username} -l {location}"
    else:
        log_file = "/var/log/setup-skyport.log"
        command = (
            f"/opt/swm/current/scripts/setup-skyport.sh -u {username} -l {location}"
        )

    print(f"Run command: {command}")
    with open(log_file, "w") as log_file:
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )

        process.wait()
        if process.returncode == 0:
            print(
                "\n"
                "Sky Port has been initialized.\n"
                "Please ensure now that Azure is configured, see HOWTO/AZURE.md.\n"
                "The container will be stopped now. Start again when Azure is ready.\n"
            )
        else:
            print(
                f"Setup has failed with exit code {process.returncode}.\n"
                "See /var/log/setup-skyport.log for details."
            )
            sys.exit(1)


def ask_clean_spool(spool_directory: str) -> None:
    while True:
        if not os.path.exists(spool_directory):
            break
        if os.listdir(spool_directory):
            answer = (
                input(f"Recreate configuration located in {spool_directory}? [N] ")
                .strip()
                .lower()
            )
            if answer in ["yes", "y"]:
                if DEV_MODE:
                    print(
                        f"SKIP spool directory removal in dev mode: {spool_directory}"
                    )
                else:
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
    with open(file_path, "w") as file:
        pass


def parse_args() -> None:
    parser = argparse.ArgumentParser(description="Parse --dev flag")
    parser.add_argument("--dev", action="store_true", help="Enable development mode")
    args = parser.parse_args()

    global DEV_MODE
    DEV_MODE = args.dev


def main() -> None:
    parse_args()

    username = get_username()
    if not username:
        print("User name is unknown")
        sys.exit(1)

    home = get_user_home(username)
    if not home:
        print("User home is unknown")
        sys.exit(1)

    ensure_system_user_exists(username)

    if DEV_MODE:
        skyport_initialized_file = "/tmp/skyport-initialized"
    else:
        skyport_initialized_file = "/skyport-initialized"
    if os.path.exists(skyport_initialized_file):
        print(f"File exists: {skyport_initialized_file}")
        if not warm_up_cache(username, home):
            sys.exit(1)
        if process := run_supervisord(username):
            print(f"Supervisor process terminated")
            process.terminate()
            process.wait()
            sys.exit(0)
        sys.exit(1)

    location = get_location()
    if not location:
        print("Location is unknown")
        sys.exit(1)

    if DEV_MODE:
        spool_directory = f"/tmp/swm-spool.tmp"
    else:
        spool_directory = f"{home}/.swm/spool"
    ask_clean_spool(spool_directory)

    if os.path.islink(spool_directory):
        print(f"Remove symlink: {spool_directory}")
        os.remove(spool_directory)

    if not os.path.exists(spool_directory):
        print(f"Create spool directory: {spool_directory}")
        os.makedirs(spool_directory)

    ensure_symlinks(home)
    if not os.listdir(spool_directory):
        print(f"Spool directory is empty: {spool_directory}")
        setup_skyport(username, location)
    else:
        if not warm_up_cache(username, home):
            sys.exit(1)
        if not ensure_worker_exists():
            sys.exit(1)
        if process := run_supervisord(username, pipe=True):
            print(f"Supervisor process terminated (piped)")
            process.terminate()
            process.wait()

    touch(skyport_initialized_file)


if __name__ == "__main__":
    main()
