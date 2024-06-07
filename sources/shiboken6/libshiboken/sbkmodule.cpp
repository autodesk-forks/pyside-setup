// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#include "sbkmodule.h"
#include "autodecref.h"
#include "basewrapper.h"
#include "bindingmanager.h"
#include "sbkstring.h"
#include "sbkcppstring.h"
#include "sbkconverter_p.h"

#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <cstring>

/// This hash maps module objects to arrays of converters.
using ModuleConvertersMap = std::unordered_map<PyObject *, SbkConverter **> ;

/// This hash maps module objects to arrays of Python types.
using ModuleTypesMap = std::unordered_map<PyObject *, Shiboken::Module::TypeInitStruct *> ;

struct TypeCreationStruct
{
    Shiboken::Module::TypeCreationFunction func;
    std::vector<std::string> subtypeNames;
};

/// This hash maps type names to type creation structs.
using NameToTypeFunctionMap = std::unordered_map<std::string, TypeCreationStruct> ;

/// This hash maps module objects to maps of names to functions.
using ModuleToFuncsMap = std::unordered_map<PyObject *, NameToTypeFunctionMap> ;

/// All types produced in imported modules are mapped here.
static ModuleTypesMap moduleTypes;
static ModuleConvertersMap moduleConverters;
static ModuleToFuncsMap moduleToFuncs;

namespace Shiboken
{
namespace Module
{

// PYSIDE-2404: Replacing the arguments generated by cpythonTypeNameExt
//              by a function call.
LIBSHIBOKEN_API PyTypeObject *get(TypeInitStruct &typeStruct)
{
    if (typeStruct.type != nullptr)
        return typeStruct.type;

    static PyObject *sysModules = PyImport_GetModuleDict();

    // The slow path for initialization.
    // We get the type by following the chain from the module.
    // As soon as types[index] gets filled, we can stop.

    std::string_view names(typeStruct.fullName);
    const bool usePySide = names.compare(0, 8, "PySide6.") == 0;
    auto dotPos = usePySide ? names.find('.', 8) : names.find('.');
    auto startPos = dotPos + 1;
    AutoDecRef modName(String::fromCppStringView(names.substr(0, dotPos)));
    auto *modOrType = PyDict_GetItem(sysModules, modName);
    if (modOrType == nullptr) {
        PyErr_Format(PyExc_SystemError, "Module \"%U\" should already be in sys.modules",
                                        modName.object());
        return nullptr;
    }

    do {
        dotPos = names.find('.', startPos);
        auto typeName = dotPos != std::string::npos
                        ? names.substr(startPos, dotPos - startPos)
                        : names.substr(startPos);
        startPos = dotPos + 1;
        AutoDecRef obTypeName(String::fromCppStringView(typeName));
        modOrType = PyObject_GetAttr(modOrType, obTypeName);
    } while (typeStruct.type == nullptr && dotPos != std::string::npos);

    return typeStruct.type;
}

static void incarnateHelper(PyObject *module, const std::string_view names,
                            const NameToTypeFunctionMap &nameToFunc)
{
    auto dotPos = names.find('.');
    std::string::size_type startPos = 0;
    auto *modOrType{module};
    while (dotPos != std::string::npos) {
        auto typeName = names.substr(startPos, dotPos - startPos);
        AutoDecRef obTypeName(String::fromCppStringView(typeName));
        modOrType = PyObject_GetAttr(modOrType, obTypeName);
        startPos = dotPos + 1;
        dotPos = names.find('.', startPos);
    }
    // now we have the type to create.
    auto funcIter = nameToFunc.find(std::string(names));
    // - call this function that returns a PyTypeObject
    auto tcStruct = funcIter->second;
    auto initFunc = tcStruct.func;
    PyTypeObject *type = initFunc(modOrType);
    auto name = names.substr(startPos);
    PyObject_SetAttrString(modOrType, name.data(), reinterpret_cast<PyObject *>(type));
}

static void incarnateSubtypes(PyObject *module,
                              const std::vector<std::string> &nameList,
                              NameToTypeFunctionMap &nameToFunc)
{
    for (auto const & tableIter : nameList) {
        std::string_view names(tableIter);
        incarnateHelper(module, names, nameToFunc);
    }
}

static PyTypeObject *incarnateType(PyObject *module, const char *name,
                                   NameToTypeFunctionMap &nameToFunc)
{
    // - locate the name and retrieve the generating function
    auto funcIter = nameToFunc.find(name);
    if (funcIter == nameToFunc.end()) {
        // attribute does really not exist.
        PyErr_SetNone(PyExc_AttributeError);
        return nullptr;
    }
    // - call this function that returns a PyTypeObject
    auto tcStruct = funcIter->second;
    auto initFunc = tcStruct.func;
    auto *modOrType{module};

    // PYSIDE-2404: Make sure that no switching happens during type creation.
    auto saveFeature = initSelectableFeature(nullptr);
    PyTypeObject *type = initFunc(modOrType);
    if (!tcStruct.subtypeNames.empty())
        incarnateSubtypes(module, tcStruct.subtypeNames, nameToFunc);
    initSelectableFeature(saveFeature);

    // - assign this object to the name in the module
    auto *res = reinterpret_cast<PyObject *>(type);
    Py_INCREF(res);
    PyModule_AddObject(module, name, res);   // steals reference
    // - remove the entry, if not by something cleared.
    if (!nameToFunc.empty())
        nameToFunc.erase(funcIter);
    // - return the PyTypeObject.
    return type;
}

// PYSIDE-2404: Make sure that the mentioned classes really exist.
// Used in `Pyside::typeName`. Because the result will be cached by
// the creation of the type(s), this is efficient.
void loadLazyClassesWithName(const char *name)
{
    for (auto const & tableIter : moduleToFuncs) {
        auto nameToFunc = tableIter.second;
        auto funcIter = nameToFunc.find(name);
        if (funcIter != nameToFunc.end()) {
            // attribute exists in the lazy types.
            auto *module = tableIter.first;
            incarnateType(module, name, nameToFunc);
        }
    }
}

// PYSIDE-2404: Completely load all not yet loaded classes.
//              This is needed to resolve a star import.
void resolveLazyClasses(PyObject *module)
{
    // - locate the module in the moduleTofuncs mapping
    auto tableIter = moduleToFuncs.find(module);
    if (tableIter == moduleToFuncs.end())
        return;

    // - see if there are still unloaded elements
    auto &nameToFunc = tableIter->second;

    // - incarnate all types.
    while (!nameToFunc.empty()) {
        auto it = nameToFunc.begin();
        auto attrNameStr = it->first;
        incarnateType(module, attrNameStr.c_str(), nameToFunc);
    }
}

// PYSIDE-2404: Override the gettattr function of modules.
static getattrofunc origModuleGetattro{};

// PYSIDE-2404: Use the patched module getattr to do on-demand initialization.
//              This modifies _all_ modules but should have no impact.
static PyObject *PyModule_lazyGetAttro(PyObject *module, PyObject *name)
{
    // - check if the attribute is present and return it.
    auto *attr = PyObject_GenericGetAttr(module, name);
    // - we handle AttributeError, only.
    if (!(attr == nullptr && PyErr_ExceptionMatches(PyExc_AttributeError)))
        return attr;

    PyErr_Clear();
    // - locate the module in the moduleTofuncs mapping
    auto tableIter = moduleToFuncs.find(module);
    // - if this is not our module, use the original
    if (tableIter == moduleToFuncs.end())
        return origModuleGetattro(module, name);

    // - locate the name and retrieve the generating function
    const char *attrNameStr = Shiboken::String::toCString(name);
    auto &nameToFunc = tableIter->second;
    // - create the real type and handle subtypes
    auto *type = incarnateType(module, attrNameStr, nameToFunc);
    auto *ret = reinterpret_cast<PyObject *>(type);
    // - if attribute does really not exist use the original
    if (ret == nullptr && PyErr_ExceptionMatches(PyExc_AttributeError)) {
        PyErr_Clear();
        return origModuleGetattro(module, name);
    }
    return ret;
}

// PYSIDE-2404: Supply a new module dir for not yet visible entries.
//              This modification is only for "our" modules.
static PyObject *_module_dir_template(PyObject * /* self */, PyObject *args)
{
    static PyObject *const _dict = Shiboken::String::createStaticString("__dict__");
    // The dir function must replace all of the builtin function.
    PyObject *module{};
    if (!PyArg_ParseTuple(args, "O", &module))
        return nullptr;

    auto tableIter = moduleToFuncs.find(module);
    assert(tableIter != moduleToFuncs.end());
    Shiboken::AutoDecRef dict(PyObject_GetAttr(module, _dict));
    auto *ret = PyDict_Keys(dict);
    // Now add all elements that were not yet in the dict.
    auto &nameToFunc = tableIter->second;
    for (const auto &funcIter : nameToFunc) {
        const char *name = funcIter.first.c_str();
        Shiboken::AutoDecRef pyName(PyUnicode_FromString(name));
        PyList_Append(ret, pyName);
    }
    return ret;
}

static PyMethodDef module_methods[] = {
    {"__dir__", (PyCFunction)_module_dir_template, METH_VARARGS, nullptr},
    {nullptr, nullptr, 0, nullptr}
};

// Python 3.8 - 3.12
static int const LOAD_CONST_312 = 100;
static int const IMPORT_NAME_312 = 108;
// Python 3.13
static int const LOAD_CONST_313 = 83;
static int const IMPORT_NAME_313 = 75;

static bool isImportStar(PyObject *module)
{
    // Find out whether we have a star import. This must work even
    // when we have no import support from feature.
    static PyObject *const _f_code = Shiboken::String::createStaticString("f_code");
    static PyObject *const _f_lasti = Shiboken::String::createStaticString("f_lasti");
    static PyObject *const _f_back = Shiboken::String::createStaticString("f_back");
    static PyObject *const _co_code = Shiboken::String::createStaticString("co_code");
    static PyObject *const _co_consts = Shiboken::String::createStaticString("co_consts");
    static PyObject *const _co_names = Shiboken::String::createStaticString("co_names");

    static int LOAD_CONST = _PepRuntimeVersion() < 0x030D00 ? LOAD_CONST_312 : LOAD_CONST_313;
    static int IMPORT_NAME = _PepRuntimeVersion() < 0x030D00 ? IMPORT_NAME_312 : IMPORT_NAME_313;

    auto *obFrame = reinterpret_cast<PyObject *>(PyEval_GetFrame());
    if (obFrame == nullptr)
        return true;            // better assume worst-case.

    Py_INCREF(obFrame);
    AutoDecRef dec_frame(obFrame);

    // Calculate the offset of the running import_name opcode on the stack.
    // Right before that there must be a load_const with the tuple `("*",)`.
    while (dec_frame.object() != Py_None) {
        AutoDecRef dec_f_code(PyObject_GetAttr(dec_frame, _f_code));
        AutoDecRef dec_co_code(PyObject_GetAttr(dec_f_code, _co_code));
        AutoDecRef dec_f_lasti(PyObject_GetAttr(dec_frame, _f_lasti));
        Py_ssize_t f_lasti = PyLong_AsSsize_t(dec_f_lasti);
        Py_ssize_t code_len;
        char *co_code{};
        PyBytes_AsStringAndSize(dec_co_code, &co_code, &code_len);
        uint8_t opcode2 = co_code[f_lasti];
        uint8_t opcode1 = co_code[f_lasti - 2];
        if (opcode1 == LOAD_CONST && opcode2 == IMPORT_NAME) {
            uint8_t oparg1 = co_code[f_lasti - 1];
            uint8_t oparg2 = co_code[f_lasti + 1];
            AutoDecRef dec_co_consts(PyObject_GetAttr(dec_f_code, _co_consts));
            auto *fromlist = PyTuple_GetItem(dec_co_consts, oparg1);
            if (PyTuple_Check(fromlist) && PyTuple_Size(fromlist) == 1
                    && Shiboken::String::toCString(PyTuple_GetItem(fromlist, 0))[0] == '*') {
                AutoDecRef dec_co_names(PyObject_GetAttr(dec_f_code, _co_names));
                const char *name = String::toCString(PyTuple_GetItem(dec_co_names, oparg2));
                const char *modName = PyModule_GetName(module);
                if (std::strcmp(name, modName) == 0)
                    return true;
            }
        }
        dec_frame.reset(PyObject_GetAttr(dec_frame, _f_back));
    }
    return false;
}

// PYSIDE-2404: These modules produce ambiguous names which we cannot handle, yet.
static std::unordered_set<std::string> dontLazyLoad{
    "testbinding"
};

static const std::unordered_set<std::string> knownModules{
    "shiboken6.Shiboken",
    "minimal",
    "other",
    "sample",
    "smart",
    "scriptableapplication",
    "testbinding"
};

static bool canNotLazyLoad(PyObject *module)
{
    const char *modName = PyModule_GetName(module);

    // There are no more things that must be disabled :-D
    return dontLazyLoad.find(modName) != dontLazyLoad.end();
}

static bool shouldLazyLoad(PyObject *module)
{
    const char *modName = PyModule_GetName(module);

    if (knownModules.find(modName) != knownModules.end())
        return true;
    return std::strncmp(modName, "PySide6.", 8) == 0;
}

static int lazyLoadDefault()
{
#ifndef PYPY_VERSION
    int result = 1;
#else
    int result = 0;
#endif
    if (auto *flag = getenv("PYSIDE6_OPTION_LAZY"))
        result = std::atoi(flag);
    return result;
}

void checkIfShouldLoadImmediately(PyObject *module, const std::string &name,
                                  const NameToTypeFunctionMap &nameToFunc)
{
    static const int value = lazyLoadDefault();

    // PYSIDE-2404: Lazy Loading
    //
    // Options:
    //   0  - switch lazy loading off.
    //   1  - lazy loading for all known modules.
    //   3  - lazy loading for any module.
    //
    // By default we lazy load all known modules (option = 1).
    if (value == 0                                  // completely disabled
        || canNotLazyLoad(module)                   // for some reason we cannot lazy load
        || (value == 1 && !shouldLazyLoad(module))  // not a known module
        ) {
        incarnateHelper(module, name, nameToFunc);
    }
}

void AddTypeCreationFunction(PyObject *module,
                             const char *name,
                             TypeCreationFunction func)
{
    // - locate the module in the moduleTofuncs mapping
    auto tableIter = moduleToFuncs.find(module);
    assert(tableIter != moduleToFuncs.end());
    // - Assign the name/generating function tcStruct.
    auto &nameToFunc = tableIter->second;
    TypeCreationStruct tcStruct{func, {}};
    auto nit = nameToFunc.find(name);
    if (nit == nameToFunc.end())
        nameToFunc.insert(std::make_pair(name, tcStruct));
    else
        nit->second = tcStruct;

    checkIfShouldLoadImmediately(module, name, nameToFunc);
}

void AddTypeCreationFunction(PyObject *module,
                             const char *containerName,
                             TypeCreationFunction func,
                             const char *namePath)
{
    // - locate the module in the moduleTofuncs mapping
    auto tableIter = moduleToFuncs.find(module);
    assert(tableIter != moduleToFuncs.end());
    // - Assign the name/generating function tcStruct.
    auto &nameToFunc = tableIter->second;
    auto nit = nameToFunc.find(containerName);

    // - insert namePath into the subtype vector of the main type.
    nit->second.subtypeNames.push_back(namePath);
    // - insert it also as its own entry.
    nit = nameToFunc.find(namePath);
    TypeCreationStruct tcStruct{func, {}};
    if (nit == nameToFunc.end())
        nameToFunc.insert(std::make_pair(namePath, tcStruct));
    else
        nit->second = tcStruct;

    checkIfShouldLoadImmediately(module, namePath, nameToFunc);
}

PyObject *import(const char *moduleName)
{
    PyObject *sysModules = PyImport_GetModuleDict();
    PyObject *module = PyDict_GetItemString(sysModules, moduleName);
    if (module != nullptr)
        Py_INCREF(module);
    else
        module = PyImport_ImportModule(moduleName);

    if (module == nullptr)
        PyErr_Format(PyExc_ImportError, "could not import module '%s'", moduleName);

    return module;
}

// PYSIDE-2404: Redirecting import for "import *" support.
//
// The first import will be handled by the isImportStar function.
// But the same module might be imported twice, which would give no
// introspection due to module caching.

static PyObject *origImportFunc{};

static PyObject *lazy_import(PyObject * /* self */, PyObject *args, PyObject *kwds)
{
    auto *ret = PyObject_Call(origImportFunc, args, kwds);
    if (ret != nullptr) {
        // PYSIDE-2404: Support star import when lazy loading.
        if (PyTuple_Size(args) >= 4) {
            auto *fromlist = PyTuple_GetItem(args, 3);
            if (PyTuple_Check(fromlist) && PyTuple_Size(fromlist) == 1
                    && Shiboken::String::toCString(PyTuple_GetItem(fromlist, 0))[0] == '*')
                Shiboken::Module::resolveLazyClasses(ret);
        }
    }
    return ret;
}

static PyMethodDef lazy_methods[] = {
    {"__lazy_import__", (PyCFunction)lazy_import, METH_VARARGS | METH_KEYWORDS, nullptr},
    {nullptr, nullptr, 0, nullptr}
};

PyObject *create(const char * /* modName */, void *moduleData)
{
    static auto *sysModules = PyImport_GetModuleDict();
    static auto *builtins = PyEval_GetBuiltins();
    static auto *partial = Pep_GetPartialFunction();
    static bool lazy_init{};

    Shiboken::init();
    auto *module = PyModule_Create(reinterpret_cast<PyModuleDef *>(moduleData));

    // Setup of a dir function for "missing" classes.
    auto *moduleDirTemplate = PyCFunction_NewEx(module_methods, nullptr, nullptr);
    // Turn this function into a bound object, so we have access to the module.
    auto *moduleDir = PyObject_CallFunctionObjArgs(partial, moduleDirTemplate, module, nullptr);
    PyModule_AddObject(module, module_methods->ml_name, moduleDir);  // steals reference
    // Insert an initial empty table for the module.
    NameToTypeFunctionMap empty;
    moduleToFuncs.insert(std::make_pair(module, empty));

    // A star import must be done unconditionally. Use the complete name.
    if (isImportStar(module))
        dontLazyLoad.insert(PyModule_GetName(module));

    if (!lazy_init) {
        // Install the getattr patch.
        origModuleGetattro = PyModule_Type.tp_getattro;
        PyModule_Type.tp_getattro = PyModule_lazyGetAttro;
        // Add the lazy import redirection, keeping a reference.
        origImportFunc = PyDict_GetItemString(builtins, "__import__");
        Py_INCREF(origImportFunc);
        AutoDecRef func(PyCFunction_NewEx(lazy_methods, nullptr, nullptr));
        PyDict_SetItemString(builtins, "__import__", func);
        lazy_init = true;
    }
    // PYSIDE-2404: Nuitka inserts some additional code in standalone mode
    //              in an invisible virtual module (i.e. `QtCore-postLoad`)
    //              that gets imported before the running import can call
    //              `_PyImport_FixupExtensionObject` which does the insertion
    //              into `sys.modules`. This can cause a race condition.
    // Insert the module early into the module dict to prevend recursion.
    PyDict_SetItemString(sysModules, PyModule_GetName(module), module);
    // Clear the non-existing name cache because we have a new module.
    Shiboken::Conversions::clearNegativeLazyCache();
    return module;
}

void registerTypes(PyObject *module, TypeInitStruct *types)
{
    auto iter = moduleTypes.find(module);
    if (iter == moduleTypes.end())
        moduleTypes.insert(std::make_pair(module, types));
}

TypeInitStruct *getTypes(PyObject *module)
{
    auto iter = moduleTypes.find(module);
    return (iter == moduleTypes.end()) ? 0 : iter->second;
}

void registerTypeConverters(PyObject *module, SbkConverter **converters)
{
    auto iter = moduleConverters.find(module);
    if (iter == moduleConverters.end())
        moduleConverters.insert(std::make_pair(module, converters));
}

SbkConverter **getTypeConverters(PyObject *module)
{
    auto iter = moduleConverters.find(module);
    return (iter == moduleConverters.end()) ? 0 : iter->second;
}

} } // namespace Shiboken::Module
