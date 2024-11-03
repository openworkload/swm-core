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
# NOTE: When we run this script, then there is no generated sys.config, but only a template of it.
# Thus the service stoppage (in case it was started before) ends with the error "Invalid node name".
# Also the stoppage will fail because old and new cookies may differ.

import argparse
import datetime
import getpass
import logging
import os
import sys
import shutil
import socket
import time
import uuid
import pwd

from subprocess import Popen
from subprocess import PIPE

PRODUCT = "swm"
SERVICES_DIR = "/lib/systemd/system"
LOG_FILE = "/tmp/swm-setup.log"
LOG = logging.getLogger("cm-scale")
SWM_VERSION_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def setup_logger(opts):
    global LOG
    for hdlr in LOG.handlers[:]:
        LOG.removeHandler(hdlr)
    fh = logging.FileHandler(LOG_FILE)
    fmr = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
    fh.setFormatter(fmr)
    LOG.addHandler(fh)

    if opts.get("DEBUG", False):
        LOG.setLevel(logging.DEBUG)
    else:
        LOG.setLevel(logging.INFO)

    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(fmr)
    LOG.addHandler(ch)


def run(exe, args, env, exit_on_fail = True, verbose = True, user = None):
    def normalize(x):
        return list(filter(None, x.decode("utf-8", "strict").split("\n")))

    cmdline = exe + ' ' + ' '.join(args)
    if user == "root":
        cmdline = f"runuser -u {user} {cmdline}"
    LOG.info("Run " + "'" + cmdline + "'")
    filename = os.path.basename(exe)

    try:
        pipe = Popen(cmdline, shell=True, stdout=PIPE, stderr=PIPE, env=env)
        (stdout, stderr) = pipe.communicate()

        stdout = normalize(stdout)
        stderr = normalize(stderr)

        if verbose:
            for line in stdout:
                LOG.info("     " + filename + " stdout: " + str(line))
            for line in stderr:
                LOG.info("     " + filename + " stderr: " + str(line))

        if pipe.wait() != 0:
            if exit_on_fail:
                LOG.error("     " + filename + " exit code: " + str(pipe.returncode))
                sys.exit(1)
        else:
            LOG.info("     " + filename + " exit code: " + str(pipe.returncode))
    except Exception as e:
        LOG.error("     " + filename + " execution: " + e)
        sys.exit(1)
    return (stdout, stderr)


def  write_file(filepath, content):
    try:
        LOG.info("Write %s" % filepath)
        with open(filepath, "w", encoding='utf-8') as fh:
            fh.write(content)
    except Exception as e:
        LOG.error("Could not write %s: %s" % (filepath, e))
        sys.exit(1)


def question(msg, default, ispath=True):
    msgfull = (msg + " [%s]: ") % default
    print(msgfull, end="",flush=True)
    answer = sys.stdin.readline()
    answer = answer.strip()
    if len(answer) == 0:
        return default
    if ispath:
        answer = os.path.expanduser(answer)
        answer = os.path.abspath(answer)
        base = os.path.dirname(answer)
        if os.path.isdir(base):
            return answer
        else:
            return default
    return answer


def make_dirs(dir):
    if not os.path.exists(dir):
        try:
            LOG.info("Making dir: " + dir)
            os.makedirs(dir, 0o700)
        except OSError as e:
            LOG.error("could not create %s: %s" % (dir, e))
            sys.exit(1)


def ensure_dirs(opts):
    make_dirs(opts["SWM_SPOOL"])


def generate_configs(opts):
    generate_service_file(opts)


def generate_service_file(opts):
    if opts["NO_SERVICE"]:
        return
    if opts.get("TESTING", False):
        LOG.info("Service file will not be installed")
        return
    tmplfp = os.path.join(opts["SWM_PRIV_DIR"], "setup", "systemd-service.linux")
    LOG.info("service template file: %s" % tmplfp)
    try:
        with open(tmplfp, "r") as f:
            lines = f.readlines()
            template = ''.join(lines)
    except OSError as e:
        LOG.error("Could not read %s: %s" % (tmplfp, e))
        sys.exit(1)
    script = os.path.join(SWM_VERSION_DIR, "bin", PRODUCT)
    env = os.path.join(SWM_VERSION_DIR, "scripts", "swm.env")
    LOG.info("init script path: %s" % script)
    template = template.replace("{SCRIPT}", script)
    template = template.replace("{ENV}", env)
    service_fp = os.path.join(SERVICES_DIR, PRODUCT + ".service")
    write_file(service_fp, template)


def env(opts):
    command = ['bash', '-c', 'source {env}'.format(env=os.path.join(SWM_VERSION_DIR, "scripts", "swm.env"))]
    LOG.info("Run '%s'" % ' '.join(command))

    envs = os.environ
    for (key,val) in opts.items():
        if isinstance(val, str) and key.startswith("SWM"):
            envs[key] = val

    proc = Popen(command, stdout = PIPE, env=envs)
    for line in proc.stdout:
        line = line.decode()
        (key, _, value) = line.partition("=")
        os.environ[key] = value.strip()
    proc.communicate()


def get_div_arg(opts):
    div_arg = "-x"
    if opts["DIVISION"] == "grid":
        div_arg = "-g"
    elif opts["DIVISION"] == "cluster" and not opts.get("SWM_SKY_PORT", None):
        div_arg = "-c"
    return div_arg


def spawn_vnode(opts):
    if opts["DIVISION"] not in ("grid", "cluster"):
        return

    if opts.get("TESTING", False):
        args = [get_div_arg(opts), "-b"]
        script = os.path.join(SWM_VERSION_DIR, "scripts", "run-in-shell.sh")
    else:
        args = ["daemon"]
        script = os.path.join(SWM_VERSION_DIR, "bin", PRODUCT)
        #opts["SWM_MNESIA_DIR"] = os.path.join(opts["SWM_SPOOL"], opts["SWM_SNAME"] + "@" + opts["SWM_HOST"], "confdb")

    os.environ["SWM_MODE"] = "MAINT"
    envs = os.environ
    for (key,val) in opts.items():
        if isinstance(val, str):
            envs[key] = val
    for key,val in envs.items():
        if key.startswith("SWM"):
            LOG.info("export %s=%s" % (key, val))

    run(script, args, envs, user=opts["SWM_ADMIN_USER"])


def wait_vnode(opts):
    def poll(ping_vnode, n):
        while n > 0:
            (stdout, stderr) = ping_vnode()
            for line in stdout:
                if line == "pong":
                    time.sleep(5)
                    return
            time.sleep(1)
            n = n - 1
        ping_vnode(exit_on_fail = True, verbose = True)

    if opts["DIVISION"] not in ("grid", "cluster"):
        return

    if opts.get("TESTING", False):
        script = os.path.join(SWM_VERSION_DIR, "scripts", "run-in-shell.sh")
        args = [get_div_arg(opts), "-p"]
    else:
        script = os.path.join(SWM_VERSION_DIR, "bin", "swm")
        args = ["ping"]

    poll(lambda exit_on_fail = False, verbose = False: run(script, args, os.environ, exit_on_fail, verbose), 60)


def stop_vnode(opts, exit_on_fail=True):
    if opts["DIVISION"] not in ("grid", "cluster"):
        return

    if opts.get("TESTING", False):
        script = os.path.join(SWM_VERSION_DIR, "scripts", "run-in-shell.sh")
        args = [get_div_arg(opts), "-s"]
        run(script, args, os.environ)
    else:
        script = os.path.join(SWM_VERSION_DIR, "bin", "swm")
        if os.path.exists(script):
            run(script, ["stop"], os.environ, exit_on_fail)


def run_ctl(args, opts):
    if opts.get("TESTING", False):
        ctl = os.path.join(SWM_VERSION_DIR, "scripts", "swmctl")
    else:
        ctl = os.path.join(SWM_VERSION_DIR, "bin", "swmctl")

    envs = os.environ
    for (key,val) in opts.items():
        if isinstance(val, str):
            envs[key] = val

    capath = os.path.join(opts["SWM_SPOOL"], "secure/cluster/cert.pem")
    envs["SWM_CLUSTER_CA"] = capath
    run(ctl, args, envs)


def load_db_configs(opts):
    if opts["DIVISION"] not in ["grid", "cluster"]:
        LOG.info(f'Skip loading db configs (division: {opts["DIVISION"]})')
        return

    schema = os.path.join(opts["SWM_PRIV_DIR"], "schema.json")
    run_ctl(["global", "update", "schema", schema], opts)
    base_config = os.path.join(opts["SWM_PRIV_DIR"], "base.config")
    run_ctl(["global", "import", base_config], opts)
    if "EXTRA_CONFIG" in opts:
        run_ctl(["global", "import", opts["EXTRA_CONFIG"]], opts)
    add_default_users(opts)


def run_create_cert(args, opts):
    if opts.get("TESTING", False):
        script = os.path.join(SWM_VERSION_DIR, "scripts", "swm-create-cert")
    else:
        script = os.path.join(SWM_VERSION_DIR, "bin", "swm-create-cert")
    envs = os.environ
    for (key,val) in opts.items():
        if isinstance(val, str):
            envs[key] = val

    if "SWM_ADMIN_USER" in opts:
        run(script, args, envs, user=opts["SWM_ADMIN_USER"])
    else:
        run(script, args, envs)


def generate_certificates(opts):
    if opts["DIVISION"] != "grid" and not opts["SWM_SKY_PORT"]:
        LOG.info("Skip certificates generation")
        return
    LOG.info("Generate certificates")
    run_create_cert(["grid"], opts)
    run_create_cert(["cluster"], opts)
    run_create_cert(["user", opts["SWM_ADMIN_USER"], opts["SWM_ADMIN_ID"]], opts)
    run_create_cert(["host"], opts)
    if opts["SWM_SKY_PORT"]:
        run_create_cert(["skyport"], opts)
    else:
        run_create_cert(["node"], opts)
    install_admin_cert(opts)
    create_chain_cert(opts)


def create_chain_cert(opts):
    filenames = ['/opt/swm/spool/secure/cluster/cert.pem', '/opt/swm/spool/secure/grid/cert.pem']
    with open('/opt/swm/spool/secure/cluster/ca-chain-cert.pem', 'w') as outfile:
        for fname in filenames:
            with open(fname) as infile:
                outfile.write(infile.read())


def get_user_home(username: str) -> str:
    try:
        return pwd.getpwnam(username).pw_dir
    except KeyError:
        LOG.error(f"User '{username}' not found")
        sys.exit(1)


def install_admin_cert(opts):
    home = get_user_home(opts["SWM_USER"])
    if not home:
        LOG.error("User home is unknown is not defined")
        sys.exit(1)
    src_dir = os.path.join(opts["SWM_SPOOL"], "secure", "users", opts["SWM_ADMIN_USER"])
    dst_dir = os.path.join(home, ".swm")
    make_dirs(dst_dir)

    for file in ["cert.pem", "key.pem"]:
        src = os.path.join(src_dir, file)
        dst = os.path.join(dst_dir, file)

        if os.path.exists(dst):
            LOG.info("file exists, will be replaced: %s" % dst)
            try:
                os.remove(dst)
            except IOError as e:
                LOG.error("Cannot remove: %s" % (dst, e))
                sys.exit(1)

        try:
            shutil.copyfile(src, dst, follow_symlinks=True)
        except IOError as e:
            LOG.error("Cannot copy %s -> %s: %s" % (src, dst, e))
            sys.exit(1)


def add_default_users(opts):
    LOG.info("Add default users")
    if opts["DIVISION"] not in ["grid", "cluster"]:
        LOG.info("User will not be added")
        return
    run_ctl(["user", "create", opts["SWM_ADMIN_USER"], opts["SWM_ADMIN_ID"]], opts)


def get_setup_options():
    args = get_args()
    opts = {}
    opts["SWM_USER"] = args.user_name or "root"
    opts["NO_SERVICE"] = args.no_service
    opts["SWM_SKY_PORT"] = args.skyport
    if args.spool:
        opts["SWM_SPOOL"] = args.spool
    if args.division:
        opts["DIVISION"] = args.division
    if args.testing:
        opts["TESTING"] = True # see scripts/setup-dev.linux
        opts["DEBUG"] = True
    if args.archive:
        opts["ARCHIVE"] = True
    if args.extra:
        opts["EXTRA_CONFIG"] = args.extra
    if args.extra and not os.path.exists(args.extra):
        LOG.error("No such file: " + str(args.extra))
        sys.exit(1)
    if args.prefix:
        if not os.path.exists(args.prefix):
            LOG.error("No such file: " + str(args.prefix))
            sys.exit(1)
        opts["SWM_ROOT"] = args.prefix
    if args.config:
        if not os.path.isfile(args.config):
            LOG.error("No such file: " + str(args.config))
            sys.exit(1)
        try:
            fp = open(args.config, "rt")
            while True:
                line = fp.readline()
                if not line:
                    break
                line = line.strip()
                if len(line) == 0:
                    continue
                if line[0] == "#":
                    continue
                pp = line.split("=")
                if len(pp) < 2:
                    continue
                key = pp[0].strip().replace('"', "").replace("'", "")
                val = pp[1].strip().replace('"', "").replace("'", "")
                if len(key) and len(val):
                    opts[key] = val
        except IOError as e:
            LOG.error("Cannot read %s: %s" % (args.config, e))
            sys.exit(1)
    return opts


def get_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-d", "--division",
        default='node',
        choices=['grid', 'cluster'],
        help="Configuring division name"
    )

    parser.add_argument(
        "-u", "--user-name",
        help="User name that will be admin (default: current user)"
    )

    parser.add_argument(
        "-p", "--prefix",
        help="Path to root directory (can also be defined with $SWM_ROOT)"
    )

    parser.add_argument(
        "-s", "--spool",
        help="Path to spool directory (can also be defined with $SWM_SPOOL, "
             "if not set, then $SWM_ROOT/spool is used)"
    )

    parser.add_argument(
        "-c", "--config",
        help="Path to file with default setup options"
    )

    parser.add_argument(
        "-e", "--extra",
        help="Path to file with additional DB configuration"
    )

    parser.add_argument(
        "-n", "--no-service",
        action="store_true",
        help="Do not install swm service file"
    )

    parser.add_argument(
        "-t", "--testing",
        action="store_true",
        help="Setup for testing purposes (no service file, just a spool)"
    )

    parser.add_argument(
        "-x", "--skyport",
        action="store_true",
        help="Setup Sky Port"
    )

    parser.add_argument(
        "-v", "--version",
        help="Specify version"
    )

    parser.add_argument(
        "-a", "--archive",
        action="store_true",
        help="Generate final worker SWM archive"
    )

    return parser.parse_args()


def userInput(env, default, descr, opts, replacements=[], ispath=True):
    if env not in opts:
        answer = question("Enter " + descr, default, ispath)
        opts[env] = answer
    for (x,y) in replacements:
        opts[env] = opts[env].replace(x, y)
    LOG.info("Entered " + descr + ": " + opts[env])


def set_default(env, default, descr, opts):
    if env not in opts:
        opts[env] = default
    os.environ[env] = opts[env]
    LOG.info("Using " + descr + ": " + opts[env])


def get_defaults(opts):
    set_default("SWM_VERSION",     os.environ["SWM_VERSION"],             "version",                 opts)
    set_default("SWM_ROOT",        os.environ["SWM_ROOT"],                "product directory",       opts)
    set_default("SWM_SPOOL",       os.environ["SWM_SPOOL"],               "product spool directory", opts)
    set_default("SWM_PRIV_DIR",    os.path.join(SWM_VERSION_DIR, "priv"), "priv directory",          opts)

    if "EXTRA_CONFIG" not in opts:
        if opts["DIVISION"] == "grid":
            opts["EXTRA_CONFIG"] = os.path.join(opts["SWM_PRIV_DIR"], "setup", "grid.config")
        elif opts["DIVISION"] == "cluster":
            conf = "skyport.config" if opts["SWM_SKY_PORT"] else "cluster.config"
            opts["EXTRA_CONFIG"] = os.path.join(opts["SWM_PRIV_DIR"], "setup", conf)

    if "SWM_SNAME" not in opts:
        division = opts.get("DIVISION", "")
        if division == 'grid':
            opts["SWM_SNAME"] = "ghead"
        elif division == 'cluster':
            opts["SWM_SNAME"] = "node" if opts["SWM_SKY_PORT"] else "chead1"
        else:
            opts["SWM_SNAME"] = division


def get_from_user(opts):
    default_api_port = "10001"
    if "SWM_API_PORT" not in opts:
        opts["SWM_API_PORT"] = default_api_port
    userInput("SWM_API_PORT", default_api_port, "API port", opts)

    default_parent_port = "10002"
    if "SWM_PARENT_PORT" not in opts:
        opts["SWM_PARENT_PORT"] = default_parent_port
    userInput("SWM_PARENT_PORT", default_parent_port, "Parent port", opts)

    default_parent_host = "localhost"
    if "SWM_PARENT_HOST" not in opts:
        opts["SWM_PARENT_HOST"] = default_parent_host
    userInput("SWM_PARENT_HOST", default_parent_host, "Parent host", opts)

    hostname = socket.gethostname()
    userInput("SWM_SNAME", "ghead" + "@" + hostname,
              "Division management vnode name", opts, [("{HOSTNAME}", hostname)], False)
    userInput("SWM_HOST", hostname, "Division management host name", opts,
              [("{HOSTNAME}", hostname)], False)

    admin = opts.get("SWM_USER", "root")
    opts["SWM_ADMIN_ID"] = str(uuid.uuid4())
    userInput("SWM_ADMIN_USER", admin, "administrator user", opts, [("{USER}", admin)], False)
    userInput("SWM_ADMIN_EMAIL", admin+"@"+opts["SWM_HOST"], "administrator email", opts, [("{USER}", admin)], False)

    userInput("SWM_UNIT_NAME", "Dev", "organizational unit name", opts, ispath=False)
    userInput("SWM_ORG_NAME", "Open Workload", "organization name", opts, ispath=False)
    userInput("SWM_LOCALITY", "EN", "locality name", opts, ispath=False)
    userInput("SWM_COUNTRY", "US", "country name", opts, ispath=False)


def create_archive(opts):
    spool_dir   = opts["SWM_SPOOL"]
    swm_version = opts["SWM_VERSION"]
    key_dirs = [os.path.join(spool_dir, "secure/cluster"),
                os.path.join(spool_dir, "secure/node"),
                os.path.join(spool_dir, "secure/host"),
               ]

    for key_dir in key_dirs:
        if not os.path.isdir(key_dir):
            LOG.error(f"No such key directory: {key_dir}")
            sys.exit(1)

    files = []
    if opts.get("TESTING", False):
        build_dir = os.path.join(SWM_VERSION_DIR, "_build")
        tmp_dir = os.path.join(build_dir, "packages", "swm")

        release_dir = os.path.join(build_dir, "default", "rel", "swm")
        version_dir = os.path.join(tmp_dir, opts["SWM_VERSION"])
        copy_and_overwrite(release_dir, version_dir)

        root_dir = os.path.join(build_dir, "packages")
        make_dirs(root_dir)
        files.append(version_dir)

        secure_dir = os.path.join(tmp_dir, "spool", "secure")
        make_dirs(secure_dir)
        for key_dir in key_dirs:
            copy_and_overwrite(key_dir, os.path.join(secure_dir, os.path.basename(key_dir)))
        files.append(secure_dir)
    else:
        root_dir = opts["SWM_ROOT"]
        files.append(os.path.join(root_dir, opts["SWM_VERSION"]))
        files.extend(key_dirs)

    archive = f"{root_dir}/{PRODUCT}-worker.tar.gz"
    transform_args = [
       "--transform", "'s,^.*\/swm/,,'",
       "--transform", "'s,^home/" + opts["SWM_USER"] + "/.swm,,'",
    ]
    args = transform_args + ["-czf", archive, " ".join(files)]

    run("tar", args, os.environ)
    LOG.info(f"Final worker SWM archive: {archive}")

    if opts.get("TESTING", False):
        LOG.info(f"Remove temporary directory: {tmp_dir}")
        shutil.rmtree(tmp_dir)


def copy_and_overwrite(from_path, to_path):
    LOG.info(f"Copy/overwrite {from_path} -> {to_path}")
    if os.path.exists(to_path):
        shutil.rmtree(to_path)
    shutil.copytree(from_path, to_path)


def symlink_to_current(opts):
    if opts.get("TESTING", False):
        LOG.info("Do not create a symlink 'current'")
        return

    root_dir = opts["SWM_ROOT"]

    src = os.path.join(root_dir, opts["SWM_VERSION"])
    dst = os.path.join(root_dir, "current")

    if os.path.exists(dst):
        os.unlink(dst)
    os.symlink(src, dst)

    LOG.info("Create symlink %s -> %s" % (dst, src))


def main():
    opts = get_setup_options()
    setup_logger(opts)

    env(opts)
    get_defaults(opts)

    if opts.get("ARCHIVE", False):
        create_archive(opts)
    else:
        get_from_user(opts)
        stop_vnode(opts, exit_on_fail=False)
        ensure_dirs(opts)
        generate_configs(opts)
        generate_certificates(opts)
        spawn_vnode(opts)
        wait_vnode(opts)
        load_db_configs(opts)
        stop_vnode(opts)
        create_archive(opts)
        symlink_to_current(opts)

    print("Sky Port configuration initialized")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        sys.exit(0)
