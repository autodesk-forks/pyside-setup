# Copyright (C) 2018 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

import fnmatch
import functools
import os

from pathlib import Path

from ..config import config
from ..options import OPTION
from ..utils import (copydir, copyfile, download_and_extract_7z, filter_match,
                     makefile)
from ..versions import PYSIDE, SHIBOKEN


def prepare_packages_win32(self, _vars):
    # For now, debug symbols will not be shipped into the package.
    copy_pdbs = False
    pdbs = []
    if (self.debug or self.build_type == 'RelWithDebInfo') and copy_pdbs:
        pdbs = ['*.pdb']

    # <install>/lib/site-packages/{st_package_name}/* ->
    # <setup>/{st_package_name}
    # This copies the module .pyd files and various .py files
    # (__init__, config, git version, etc.)
    copydir(
        "{site_packages_dir}/{st_package_name}",
        "{st_build_dir}/{st_package_name}",
        _vars=_vars)

    if config.is_internal_shiboken_module_build():
        # <build>/shiboken6/doc/html/* ->
        #   <setup>/{st_package_name}/docs/shiboken6
        copydir(
            f"{{build_dir}}/{SHIBOKEN}/doc/html",
            f"{{st_build_dir}}/{{st_package_name}}/docs/{SHIBOKEN}",
            force=False, _vars=_vars)

        # <install>/bin/*.dll -> {st_package_name}/
        copydir(
            "{install_dir}/bin/",
            "{st_build_dir}/{st_package_name}",
            _filter=["shiboken*.dll"],
            recursive=False, _vars=_vars)

        # <install>/lib/*.lib -> {st_package_name}/
        copydir(
            "{install_dir}/lib/",
            "{st_build_dir}/{st_package_name}",
            _filter=["shiboken*.lib"],
            recursive=False, _vars=_vars)

        # @TODO: Fix this .pdb file not to overwrite release
        # {shibokengenerator}.pdb file.
        # Task-number: PYSIDE-615
        copydir(
            f"{{build_dir}}/{SHIBOKEN}/shibokenmodule",
            "{st_build_dir}/{st_package_name}",
            _filter=pdbs,
            recursive=False, _vars=_vars)

        # pdb files for libshiboken and libpyside
        copydir(
            f"{{build_dir}}/{SHIBOKEN}/libshiboken",
            "{st_build_dir}/{st_package_name}",
            _filter=pdbs,
            recursive=False, _vars=_vars)

    if config.is_internal_shiboken_generator_build():
        # <install>/bin/*.dll -> {st_package_name}/
        copydir(
            "{install_dir}/bin/",
            "{st_build_dir}/{st_package_name}",
            _filter=["shiboken*.exe"],
            recursive=False, _vars=_vars)

        # Used to create scripts directory.
        makefile(
            "{st_build_dir}/{st_package_name}/scripts/shiboken_tool.py",
            _vars=_vars)

        # For setting up setuptools entry points.
        copyfile(
            "{install_dir}/bin/shiboken_tool.py",
            "{st_build_dir}/{st_package_name}/scripts/shiboken_tool.py",
            force=False, _vars=_vars)

        # @TODO: Fix this .pdb file not to overwrite release
        # {shibokenmodule}.pdb file.
        # Task-number: PYSIDE-615
        copydir(
            f"{{build_dir}}/{SHIBOKEN}/generator",
            "{st_build_dir}/{st_package_name}",
            _filter=pdbs,
            recursive=False, _vars=_vars)

    if config.is_internal_shiboken_generator_build() or config.is_internal_pyside_build():
        # <install>/include/* -> <setup>/{st_package_name}/include
        copydir(
            "{install_dir}/include/{cmake_package_name}",
            "{st_build_dir}/{st_package_name}/include",
            _vars=_vars)

    if config.is_internal_pyside_build():
        # <build>/pyside6/{st_package_name}/*.pdb ->
        # <setup>/{st_package_name}
        copydir(
            f"{{build_dir}}/{PYSIDE}/{{st_package_name}}",
            "{st_build_dir}/{st_package_name}",
            _filter=pdbs,
            recursive=False, _vars=_vars)

        makefile(
            "{st_build_dir}/{st_package_name}/scripts/__init__.py",
            _vars=_vars)

        # For setting up setuptools entry points
        for script in ("pyside_tool.py", "metaobjectdump.py", "project.py", "qml.py",
                       "qtpy2cpp.py", "deploy.py"):
            src = f"{{install_dir}}/bin/{script}"
            target = f"{{st_build_dir}}/{{st_package_name}}/scripts/{script}"
            copyfile(src, target, force=False, _vars=_vars)

        for script_dir in ("qtpy2cpp_lib", "deploy", "project"):
            src = f"{{install_dir}}/bin/{script_dir}"
            target = f"{{st_build_dir}}/{{st_package_name}}/scripts/{script_dir}"
            # Exclude subdirectory tests
            copydir(src, target, _filter=["*.py", "*.spec"], recursive=False, _vars=_vars)

        # <install>/bin/*.exe,*.dll -> {st_package_name}/
        filters = ["pyside*.exe", "pyside*.dll"]
        if not OPTION['NO_QT_TOOLS']:
            filters.extend(["lrelease.exe", "lupdate.exe", "uic.exe",
                            "rcc.exe", "qmllint.exe", "qmltyperegistrar.exe"
                            "assistant.exe", "designer.exe", "qmlimportscanner.exe",
                            "linguist.exe", "qmlformat.exe"])
        copydir(
            "{install_dir}/bin/",
            "{st_build_dir}/{st_package_name}",
            _filter=filters,
            recursive=False, _vars=_vars)

        # <qt>/lib/metatypes/* -> <setup>/{st_package_name}/lib/metatypes
        destination_lib_dir = "{st_build_dir}/{st_package_name}/lib"
        copydir("{qt_lib_dir}/metatypes", f"{destination_lib_dir}/metatypes",
                _filter=["*.json"],
                recursive=False, _vars=_vars)

        # <install>/lib/*.lib -> {st_package_name}/
        copydir(
            "{install_dir}/lib/",
            "{st_build_dir}/{st_package_name}",
            _filter=["pyside*.lib"],
            recursive=False, _vars=_vars)

        # <install>/share/{st_package_name}/typesystems/* ->
        #   <setup>/{st_package_name}/typesystems
        copydir(
            "{install_dir}/share/{st_package_name}/typesystems",
            "{st_build_dir}/{st_package_name}/typesystems",
            _vars=_vars)

        # <install>/share/{st_package_name}/glue/* ->
        #   <setup>/{st_package_name}/glue
        copydir(
            "{install_dir}/share/{st_package_name}/glue",
            "{st_build_dir}/{st_package_name}/glue",
            _vars=_vars)

        # <source>/pyside6/{st_package_name}/support/* ->
        #   <setup>/{st_package_name}/support/*
        copydir(
            f"{{build_dir}}/{PYSIDE}/{{st_package_name}}/support",
            "{st_build_dir}/{st_package_name}/support",
            _vars=_vars)

        # <source>/pyside6/{st_package_name}/*.pyi ->
        #   <setup>/{st_package_name}/*.pyi
        copydir(
            f"{{build_dir}}/{PYSIDE}/{{st_package_name}}",
            "{st_build_dir}/{st_package_name}",
            _filter=["*.pyi", "py.typed"],
            _vars=_vars)

        copydir(
            f"{{build_dir}}/{PYSIDE}/libpyside",
            "{st_build_dir}/{st_package_name}",
            _filter=pdbs,
            recursive=False, _vars=_vars)

        if not OPTION["NOEXAMPLES"]:
            def pycache_dir_filter(dir_name, parent_full_path, dir_full_path):
                if fnmatch.fnmatch(dir_name, "__pycache__"):
                    return False
                return True
            # examples/* -> <setup>/{st_package_name}/examples
            copydir(self.script_dir / "examples",
                    "{st_build_dir}/{st_package_name}/examples",
                    force=False, _vars=_vars, dir_filter_function=pycache_dir_filter)

        if _vars['ssl_libs_dir']:
            # <ssl_libs>/* -> <setup>/{st_package_name}/openssl
            copydir("{ssl_libs_dir}", "{st_build_dir}/{st_package_name}/openssl",
                    _filter=[
                        "libeay32.dll",
                        "ssleay32.dll"],
                    force=False, _vars=_vars)

    if config.is_internal_shiboken_module_build():
        # The C++ std library dlls need to be packaged with the
        # shiboken module, because libshiboken uses C++ code.
        copy_msvc_redist_files(_vars, Path("{build_dir}/msvc_redist".format(**_vars)))

    if config.is_internal_pyside_build() or config.is_internal_shiboken_generator_build():
        copy_qt_artifacts(self, copy_pdbs, _vars)
        copy_msvc_redist_files(_vars, Path("{build_dir}/msvc_redist".format(**_vars)))


def copy_msvc_redist_files(_vars, redist_target_path):
    # MSVC redistributable file list.
    msvc_redist = [
        "concrt140.dll",
        "msvcp140.dll",
        "ucrtbase.dll",
        "vcamp140.dll",
        "vccorlib140.dll",
        "vcomp140.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll",
        "msvcp140_1.dll",
        "msvcp140_2.dll",
        "msvcp140_codecvt_ids.dll"
    ]

    # Make a directory where the files should be extracted.
    if not redist_target_path.exists():
        redist_target_path.mkdir(parents=True)

    # Extract Qt dependency dlls when building on Qt CI.
    in_coin = os.environ.get('COIN_LAUNCH_PARAMETERS', None)
    if in_coin is not None:
        redist_url = "https://download.qt.io/development_releases/prebuilt/vcredist/"
        zip_file = "pyside_qt_deps_64_2019.7z"
        if "{target_arch}".format(**_vars) == "32":
            zip_file = "pyside_qt_deps_32_2019.7z"
        try:
            download_and_extract_7z(redist_url + zip_file, redist_target_path)
        except Exception as e:
            print(f"Download failed: {type(e).__name__}: {e}")
            print("download.qt.io is down, try with mirror")
            redist_url = "https://master.qt.io/development_releases/prebuilt/vcredist/"
            download_and_extract_7z(redist_url + zip_file, redist_target_path)
    else:
        print("Qt dependency DLLs (MSVC redist) will not be downloaded and extracted.")

    copydir(redist_target_path,
            "{st_build_dir}/{st_package_name}",
            _filter=msvc_redist, recursive=False, _vars=_vars)


def copy_qt_artifacts(self, copy_pdbs, _vars):
    built_modules = self.get_built_pyside_config(_vars)['built_modules']

    constrain_modules = None
    copy_plugins = True
    copy_qml = True
    copy_translations = True
    copy_qt_conf = True
    copy_qt_permanent_artifacts = True
    copy_msvc_redist = False
    copy_clang = False

    if config.is_internal_shiboken_generator_build():
        constrain_modules = ["Core", "Network", "Xml", "XmlPatterns"]
        copy_plugins = False
        copy_qml = False
        copy_translations = False
        copy_qt_conf = False
        copy_qt_permanent_artifacts = False
        copy_msvc_redist = True
        copy_clang = True

    # <qt>/bin/*.dll and Qt *.exe -> <setup>/{st_package_name}
    qt_artifacts_permanent = [
        "opengl*.dll",
        "d3d*.dll",
        "designer.exe",
        "linguist.exe",
        "lrelease.exe",
        "lupdate.exe",
        "lconvert.exe",
        "qtdiag.exe"
    ]

    # Choose which EGL library variants to copy.
    qt_artifacts_egl = [
        "libEGL{}.dll",
        "libGLESv2{}.dll"
    ]
    if self.qtinfo.build_type != 'debug_and_release':
        egl_suffix = '*'
    elif self.debug:
        egl_suffix = 'd'
    else:
        egl_suffix = ''
    qt_artifacts_egl = [a.format(egl_suffix) for a in qt_artifacts_egl]

    artifacts = []
    if copy_qt_permanent_artifacts:
        artifacts += qt_artifacts_permanent
        artifacts += qt_artifacts_egl

    if copy_msvc_redist:
        # The target path has to be qt_bin_dir at the moment,
        # because the extracted archive also contains the opengl32sw
        # and the d3dcompiler dlls, which are copied not by this
        # function, but by the copydir below.
        copy_msvc_redist_files(_vars, Path("{qt_bin_dir}".format(**_vars)))

    if artifacts:
        copydir("{qt_bin_dir}",
                "{st_build_dir}/{st_package_name}",
                _filter=artifacts, recursive=False, _vars=_vars)

    # <qt>/bin/*.dll and Qt *.pdbs -> <setup>/{st_package_name} part two
    # File filter to copy only debug or only release files.
    if constrain_modules:
        qt_dll_patterns = [f"Qt6{x}{{}}.dll" for x in constrain_modules]
        if copy_pdbs:
            qt_dll_patterns += [f"Qt6{x}{{}}.pdb" for x in constrain_modules]
    else:
        qt_dll_patterns = ["Qt6*{}.dll", "lib*{}.dll"]
        if copy_pdbs:
            qt_dll_patterns += ["Qt6*{}.pdb", "lib*{}.pdb"]

    def qt_build_config_filter(patterns, file_name, file_full_path):
        release = [a.format('') for a in patterns]
        debug = [a.format('d') for a in patterns]

        # If qt is not a debug_and_release build, that means there
        # is only one set of shared libraries, so we can just copy
        # them.
        if self.qtinfo.build_type != 'debug_and_release':
            if filter_match(file_name, release):
                return True
            return False

        # Setup Paths
        file_name = Path(file_name)
        file_full_path = Path(file_full_path)

        # In debug_and_release case, choosing which files to copy
        # is more difficult. We want to copy only the files that
        # match the PySide6 build type. So if PySide6 is built in
        # debug mode, we want to copy only Qt debug libraries
        # (ending with "d.dll"). Or vice versa. The problem is that
        # some libraries have "d" as the last character of the
        # actual library name (for example Qt6Gamepad.dll and
        # Qt6Gamepadd.dll). So we can't just match a pattern ending
        # in "d". Instead we check if there exists a file with the
        # same name plus an additional "d" at the end, and using
        # that information we can judge if the currently processed
        # file is a debug or release file.

        # e.g. ["Qt6Cored", ".dll"]
        file_base_name = file_name.stem
        file_ext = file_name.suffix
        # e.g. "/home/work/qt/qtbase/bin"
        file_path_dir_name = file_full_path.parent
        # e.g. "Qt6Coredd"
        maybe_debug_name = f"{file_base_name}d"
        if self.debug:
            _filter = debug

            def predicate(path):
                return not path.exists()
        else:
            _filter = release

            def predicate(path):
                return path.exists()
        # e.g. "/home/work/qt/qtbase/bin/Qt6Coredd.dll"
        other_config_path = file_path_dir_name / (maybe_debug_name + file_ext)

        if (filter_match(file_name, _filter) and predicate(other_config_path)):
            return True
        return False

    qt_dll_filter = functools.partial(qt_build_config_filter,
                                      qt_dll_patterns)
    copydir("{qt_bin_dir}",
            "{st_build_dir}/{st_package_name}",
            file_filter_function=qt_dll_filter,
            recursive=False, _vars=_vars)

    if copy_plugins:
        is_pypy = "pypy" in self.build_classifiers
        # <qt>/plugins/* -> <setup>/{st_package_name}/plugins
        plugins_target = "{st_build_dir}/{st_package_name}/plugins"
        plugin_dll_patterns = ["*{}.dll"]
        pdb_pattern = "*{}.pdb"
        if copy_pdbs:
            plugin_dll_patterns += [pdb_pattern]
        plugin_dll_filter = functools.partial(qt_build_config_filter, plugin_dll_patterns)
        copydir("{qt_plugins_dir}", plugins_target,
                file_filter_function=plugin_dll_filter,
                _vars=_vars)
        if not is_pypy:
            copydir("{install_dir}/plugins/designer",
                    f"{plugins_target}/designer",
                    _filter=["*.dll"],
                    recursive=False,
                    _vars=_vars)

    if copy_translations:
        # <qt>/translations/* -> <setup>/{st_package_name}/translations
        copydir("{qt_translations_dir}",
                "{st_build_dir}/{st_package_name}/translations",
                _filter=["*.qm", "*.pak"],
                force=False,
                _vars=_vars)

    if copy_qml:
        # <qt>/qml/* -> <setup>/{st_package_name}/qml
        qml_dll_patterns = ["*{}.dll"]
        qml_ignore_patterns = qml_dll_patterns + [pdb_pattern]
        qml_ignore = [a.format('') for a in qml_ignore_patterns]

        # Copy all files that are not dlls and pdbs (.qml, qmldir).
        copydir("{qt_qml_dir}", "{st_build_dir}/{st_package_name}/qml",
                ignore=qml_ignore,
                force=False,
                recursive=True,
                _vars=_vars)

        if copy_pdbs:
            qml_dll_patterns += [pdb_pattern]
        qml_dll_filter = functools.partial(qt_build_config_filter, qml_dll_patterns)

        # Copy all dlls (and possibly pdbs).
        copydir("{qt_qml_dir}", "{st_build_dir}/{st_package_name}/qml",
                file_filter_function=qml_dll_filter,
                force=False,
                recursive=True,
                _vars=_vars)

    if self.is_webengine_built(built_modules):
        copydir("{qt_data_dir}/resources",
                "{st_build_dir}/{st_package_name}/resources",
                _filter=None,
                recursive=False,
                _vars=_vars)

        _ext = "d" if self.debug else ""
        _filter = [f"QtWebEngineProcess{_ext}.exe"]
        copydir("{qt_bin_dir}",
                "{st_build_dir}/{st_package_name}",
                _filter=_filter,
                recursive=False, _vars=_vars)

    if copy_qt_conf:
        # Copy the qt.conf file to prefix dir.
        copyfile(f"{{build_dir}}/{PYSIDE}/{{st_package_name}}/qt.conf",
                 "{st_build_dir}/{st_package_name}",
                 _vars=_vars)

    if copy_clang:
        self.prepare_standalone_clang(is_win=True)
