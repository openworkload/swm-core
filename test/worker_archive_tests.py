#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
"""Unit checks for worker-archive secure staging (no cluster CA private key).

Run: python3 test/worker_archive_tests.py
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP_PATH = ROOT / "scripts" / "setup-swm-core.py"


def _load_setup_module():
    spec = importlib.util.spec_from_file_location("setup_swm_core", SETUP_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {SETUP_PATH}")
    mod = importlib.util.module_from_spec(spec)
    # Avoid running main; module only defines helpers when loaded.
    sys.modules["setup_swm_core"] = mod
    spec.loader.exec_module(mod)
    return mod


SETUP = _load_setup_module()


class WorkerArchiveSecureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="swm-worker-archive-test-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def _fake_spool(self) -> str:
        spool = os.path.join(self.tmp, "spool")
        cluster = os.path.join(spool, "secure", "cluster")
        node = os.path.join(spool, "secure", "node")
        host = os.path.join(spool, "secure", "host")
        os.makedirs(os.path.join(cluster, "private"), exist_ok=True)
        os.makedirs(node, exist_ok=True)
        os.makedirs(host, exist_ok=True)
        Path(cluster, "cert.pem").write_text("CLUSTER-CERT\n", encoding="utf-8")
        Path(cluster, "ca-chain-cert.pem").write_text("CHAIN\n", encoding="utf-8")
        Path(cluster, "private", "key.pem").write_text("CA-PRIVATE\n", encoding="utf-8")
        Path(cluster, "serial").write_text("01\n", encoding="utf-8")
        Path(cluster, "index.txt").write_text("", encoding="utf-8")
        Path(node, "cert.pem").write_text("NODE-CERT\n", encoding="utf-8")
        Path(node, "key.pem").write_text("NODE-KEY\n", encoding="utf-8")
        Path(host, "ssh_host_rsa_key").write_text("HOST-KEY\n", encoding="utf-8")
        return spool

    def test_stage_excludes_cluster_private(self) -> None:
        spool = self._fake_spool()
        stage = os.path.join(self.tmp, "stage-secure")
        SETUP.stage_worker_secure(spool, stage)
        self.assertTrue(os.path.isfile(os.path.join(stage, "cluster", "cert.pem")))
        self.assertTrue(os.path.isfile(os.path.join(stage, "cluster", "ca-chain-cert.pem")))
        self.assertFalse(os.path.exists(os.path.join(stage, "cluster", "private")))
        self.assertFalse(os.path.exists(os.path.join(stage, "cluster", "serial")))
        self.assertTrue(os.path.isfile(os.path.join(stage, "node", "key.pem")))
        self.assertTrue(os.path.isfile(os.path.join(stage, "host", "ssh_host_rsa_key")))

    def test_denied_members_detects_ca_private(self) -> None:
        names = [
            "1.0.0/bin/swm",
            "spool/secure/cluster/cert.pem",
            "spool/secure/cluster/private/key.pem",
            "spool/secure/node/key.pem",
        ]
        denied = SETUP.worker_archive_denied_members(names)
        self.assertEqual(denied, ["spool/secure/cluster/private/key.pem"])

    def test_assert_safe_rejects_bad_archive(self) -> None:
        bad = os.path.join(self.tmp, "bad-worker.tar.gz")
        with tarfile.open(bad, "w:gz") as tf:
            info = tarfile.TarInfo(name="spool/secure/cluster/private/key.pem")
            data = b"secret\n"
            info.size = len(data)
            tf.addfile(info, fileobj=__import__("io").BytesIO(data))
        with self.assertRaises(SystemExit):
            SETUP.assert_worker_archive_safe(bad)

    def test_assert_safe_accepts_public_only(self) -> None:
        good = os.path.join(self.tmp, "good-worker.tar.gz")
        with tarfile.open(good, "w:gz") as tf:
            for name, body in (
                ("spool/secure/cluster/cert.pem", b"cert\n"),
                ("spool/secure/cluster/ca-chain-cert.pem", b"chain\n"),
                ("spool/secure/node/key.pem", b"node\n"),
                ("spool/secure/host/ssh_host_rsa_key", b"host\n"),
            ):
                info = tarfile.TarInfo(name=name)
                info.size = len(body)
                tf.addfile(info, fileobj=__import__("io").BytesIO(body))
        SETUP.assert_worker_archive_safe(good)


if __name__ == "__main__":
    unittest.main()
