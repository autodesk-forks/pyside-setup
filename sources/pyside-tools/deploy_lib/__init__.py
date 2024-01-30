# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import sys
from pathlib import Path

MAJOR_VERSION = 6

if sys.platform == "win32":
    IMAGE_FORMAT = ".ico"
    EXE_FORMAT = ".exe"
elif sys.platform == "darwin":
    IMAGE_FORMAT = ".icns"
    EXE_FORMAT = ".bin"
else:
    IMAGE_FORMAT = ".jpg"
    EXE_FORMAT = ".bin"

DEFAULT_APP_ICON = str((Path(__file__).parent / f"pyside_icon{IMAGE_FORMAT}").resolve())
IMPORT_WARNING_PYSIDE = (f"[DEPLOY] Found 'import PySide6' in file {0}"
                         ". Use 'from PySide6 import <module>' or pass the module"
                         " needed using --extra-modules command line argument")


def get_all_pyside_modules():
    """
    Returns all the modules installed with PySide6
    """
    # They all start with `Qt` as the prefix. Removing this prefix and getting the actual
    # module name
    import PySide6
    return [module[2:] for module in PySide6.__all__]


from .commands import run_command, run_qmlimportscanner
from .nuitka_helper import Nuitka
from .config import BaseConfig, Config
from .python_helper import PythonExecutable
from .deploy_util import (cleanup, finalize, create_config_file,
                          config_option_exists, find_pyside_modules)
