#!/usr/bin/env python3
# Copyright (c) 2026-present, the Ladybird developers.
# SPDX-License-Identifier: BSD-2-Clause
# /// script
# requires-python = ">=3.10"
# dependencies = ["pymobiledevice3==11.3.1"]
# ///

import argparse
import asyncio
import logging
import plistlib
from pathlib import Path
from zipfile import ZipFile

from pymobiledevice3.remote.native_tunnel import NativeRemotedTunnel
from pymobiledevice3.services.installation_proxy import InstallationProxyService


async def install(args):
    with ZipFile(args.ipa) as package:
        info = plistlib.loads(package.read("Payload/Ladybird.app/Info.plist"))
    bundle_id = info["CFBundleIdentifier"]
    if bundle_id != "dk.klokke.ladybird":
        raise ValueError(f"Not the expected Ladybird app: {bundle_id}")

    # Explicitly close the tunnel instead of relying on the CLI's exit handler.
    async with NativeRemotedTunnel(serial=args.udid) as device:
        service = InstallationProxyService(device)
        await service.install_from_local(args.ipa, developer=args.developer)
        installed = await service.get_apps(bundle_identifiers=[bundle_id])
        if bundle_id not in installed:
            raise RuntimeError("Installation returned without the app appearing on the device")
        print(f"Verified {bundle_id} installed on {args.udid}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install Ladybird on an explicitly selected paired iPhone")
    parser.add_argument("--udid", required=True)
    parser.add_argument("--developer", action="store_true", help="Use for a development-signed IPA")
    parser.add_argument("ipa", type=Path)
    logging.basicConfig(level=logging.INFO)
    asyncio.run(install(parser.parse_args()))
