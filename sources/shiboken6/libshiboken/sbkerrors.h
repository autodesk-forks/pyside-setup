// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#ifndef SBKERRORS_H
#define SBKERRORS_H

#include "sbkpython.h"
#include "shibokenmacros.h"

/// Craving for C++20 and std::source_location::current()
#if defined(_MSC_VER)
#  define SBK_FUNC_INFO     __FUNCSIG__
#elif defined(__GNUC__)
#  define SBK_FUNC_INFO     __PRETTY_FUNCTION__
#else
#  define SBK_FUNC_INFO     __FUNCTION__
#endif

namespace Shiboken
{
namespace Errors
{

LIBSHIBOKEN_API void setInstantiateAbstractClass(const char *name);
LIBSHIBOKEN_API void setInstantiateAbstractClassDisabledWrapper(const char *name);
LIBSHIBOKEN_API void setInvalidTypeDeletion(const char *name);
LIBSHIBOKEN_API void setOperatorNotImplemented();
LIBSHIBOKEN_API void setPureVirtualMethodError(const char *name);
LIBSHIBOKEN_API void setPrivateMethod(const char *name);
LIBSHIBOKEN_API void setReverseOperatorNotImplemented();
LIBSHIBOKEN_API void setSequenceTypeError(const char *expectedType);
LIBSHIBOKEN_API void setSetterTypeError(const char *name, const char *expectedType);
LIBSHIBOKEN_API void setWrongContainerType();

/// Report an error ASAP: Instead of printing, store for later re-raise.
/// This replaces `PyErr_Print`, which cannot report errors as exception.
/// To be used in contexts where raising errors is impossible.
LIBSHIBOKEN_API void storeError();
/// Handle an error as in PyErr_Occurred(), but also check for errors which
/// were captured by `storeError`.
/// To be used in normal error checks.
LIBSHIBOKEN_API PyObject *occurred();

} // namespace Errors

namespace Warnings
{
/// Warn about invalid return value of overwritten virtual
LIBSHIBOKEN_API void warnInvalidReturnValue(const char *className, const char *functionName,
                                            const char *expectedType, const char *actualType);
LIBSHIBOKEN_API void warnDeprecated(const char *functionName);
LIBSHIBOKEN_API void warnDeprecated(const char *className, const char *functionName);
LIBSHIBOKEN_API void warnDeprecatedEnum(const char *enumName);
LIBSHIBOKEN_API void warnDeprecatedEnumValue(const char *enumName, const char *valueName);
} // namespace Warnings

} // namespace Shiboken

#endif // SBKERRORS_H
