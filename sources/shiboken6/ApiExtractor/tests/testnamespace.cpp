// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

#include "testnamespace.h"
#include "testutil.h"
#include <abstractmetalang.h>
#include <abstractmetaenum.h>
#include <typesystem.h>

#include <qtcompat.h>

#include <QtTest/QTest>

using namespace Qt::StringLiterals;

void NamespaceTest::testNamespaceMembers()
{
    const char cppCode[] = "\
    namespace Namespace\n\
    {\n\
        enum Option {\n\
            OpZero,\n\
            OpOne\n\
        };\n\
        void foo(Option opt);\n\
    };\n";
    const char xmlCode[] = "\
    <typesystem package='Foo'>\n\
        <namespace-type name='Namespace'>\n\
            <enum-type name='Option' />\n\
        </namespace-type>\n\
    </typesystem>\n";
    QScopedPointer<AbstractMetaBuilder> builder(TestUtil::parse(cppCode, xmlCode, false));
    QVERIFY(!builder.isNull());
    AbstractMetaClassList classes = builder->classes();
    const auto ns = AbstractMetaClass::findClass(classes, u"Namespace");
    QVERIFY(!ns.isNull());
    auto metaEnum = ns->findEnum(u"Option"_s);
    QVERIFY(metaEnum.has_value());
    const auto func = ns->findFunction(u"foo");
    QVERIFY(!func.isNull());
}

void NamespaceTest::testNamespaceInnerClassMembers()
{
    const char cppCode[] = "\
    namespace OuterNamespace\n\
    {\n\
        namespace InnerNamespace {\n\
            struct SomeClass {\n\
                void method();\n\
            };\n\
        };\n\
    };\n";
    const char xmlCode[] = "\
    <typesystem package='Foo'>\n\
        <namespace-type name='OuterNamespace'>\n\
            <namespace-type name='InnerNamespace'>\n\
                <value-type name='SomeClass'/>\n\
            </namespace-type>\n\
        </namespace-type>\n\
    </typesystem>\n";
    QScopedPointer<AbstractMetaBuilder> builder(TestUtil::parse(cppCode, xmlCode, false));
    QVERIFY(!builder.isNull());
    AbstractMetaClassList classes = builder->classes();
    const auto ons = AbstractMetaClass::findClass(classes, u"OuterNamespace");
    QVERIFY(!ons.isNull());
    const auto ins = AbstractMetaClass::findClass(classes, u"OuterNamespace::InnerNamespace");
    QVERIFY(!ins.isNull());
    const auto sc = AbstractMetaClass::findClass(classes, u"OuterNamespace::InnerNamespace::SomeClass");
    QVERIFY(!sc.isNull());
    const auto meth = sc->findFunction(u"method");
    QVERIFY(!meth.isNull());
}

QTEST_APPLESS_MAIN(NamespaceTest)

