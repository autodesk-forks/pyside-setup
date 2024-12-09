# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0
from __future__ import annotations

import os
import sys

from pathlib import Path
sys.path.append(os.fspath(Path(__file__).resolve().parents[1]))
from init_paths import init_test_paths
init_test_paths(False)

from PySide6.QtUiTools import QUiLoader
from PySide6.QtCore import QFile
from PySide6.QtWidgets import QApplication, QWidget


app = QApplication([])
loader = QUiLoader()
file = Path(__file__).resolve().parent / 'bug_552.ui'
assert (file.is_file())
file = QFile(file)
w = QWidget()
# An exception can't be thrown
mainWindow = loader.load(file, w)
