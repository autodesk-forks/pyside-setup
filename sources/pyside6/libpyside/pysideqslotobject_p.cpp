// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#include "pysideqslotobject_p.h"
#include "signalmanager.h"

#include <gilstate.h>

namespace PySide
{

PySideQSlotObject::PySideQSlotObject(PyObject *callable,
                                     const QByteArrayList &parameterTypes,
                                     const char *returnType) :
    QtPrivate::QSlotObjectBase(&impl),
    m_callable(callable),
    m_parameterTypes(parameterTypes),
    m_returnType(returnType)
{
    Py_INCREF(callable);
}

PySideQSlotObject::~PySideQSlotObject()
{
    Shiboken::GilState state;
    Py_DECREF(m_callable);
}

void PySideQSlotObject::call(void **args)
{
    SignalManager::callPythonMetaMethod(m_parameterTypes, m_returnType, args, m_callable);
}

void PySideQSlotObject::impl(int which, QSlotObjectBase *this_, QObject *receiver,
                             void **args, bool *ret)
{
    auto *self = static_cast<PySideQSlotObject *>(this_);
    switch (which) {
    case Destroy:
        delete self;
        break;
    case Call:
        self->call(args);
        break;
    case Compare:
    case NumOperations:
        Q_UNUSED(receiver);
        Q_UNUSED(args);
        Q_UNUSED(ret);
        break;
    }
}

} // namespace PySide
