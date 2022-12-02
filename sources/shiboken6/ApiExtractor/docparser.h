// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0
#ifndef DOCPARSER_H
#define DOCPARSER_H

#include "abstractmetalang_typedefs.h"
#include "modifications_typedefs.h"

#include <QtCore/QString>
#include <QtCore/QSharedPointer>

class AbstractMetaClass;
class DocModification;
class Documentation;

class XQuery;

struct FunctionDocumentation;

class DocParser
{
public:
    Q_DISABLE_COPY(DocParser)

    using XQueryPtr = QSharedPointer<XQuery>;

    DocParser();
    virtual ~DocParser();
    virtual void fillDocumentation(const AbstractMetaClassPtr &metaClass) = 0;

    /**
     *   Process and retrieves documentation concerning the entire
     *   module or library.
     *   \return object containing module/library documentation information
     */
    virtual Documentation retrieveModuleDocumentation() = 0;

    void setDocumentationDataDirectory(const QString& dir)
    {
        m_docDataDir = dir;
    }

    /**
     *   Informs the location of the XML data generated by the tool
     *   (e.g.: DoxyGen, qdoc) used to extract the library's documentation
     *   comment.
     *   \return the path for the directory containing the XML data created
     *   from the library's documentation beign parsed.
     */
    QString documentationDataDirectory() const
    {
        return m_docDataDir;
    }

    void setLibrarySourceDirectory(const QString& dir)
    {
        m_libSourceDir = dir;
    }
    /**
     *   Informs the location of the library being parsed. The library
     *   source code is parsed for the documentation comments.
     *   \return the path for the directory containing the source code of
     *   the library beign parsed.
     */
    QString librarySourceDirectory() const
    {
        return m_libSourceDir;
    }

    void setPackageName(const QString& packageName)
    {
        m_packageName = packageName;
    }
    /**
     *   Retrieves the name of the package (or module or library) being parsed.
     *   \return the name of the package (module/library) being parsed
     */
    QString packageName() const
    {
        return m_packageName;
    }

    /**
    *   Process and retrieves documentation concerning the entire
    *   module or library.
    *   \param name module name
    *   \return object containing module/library documentation information
    *   \todo Merge with retrieveModuleDocumentation() on next ABI change.
    */
    virtual Documentation retrieveModuleDocumentation(const QString& name) = 0;

    static bool skipForQuery(const AbstractMetaFunctionCPtr &func);

    /// Helper to return the documentation modifications for a class
    /// or a member function.
    static DocModificationList getDocModifications(const AbstractMetaClassCPtr &cppClass,
                                                   const AbstractMetaFunctionCPtr &func = {});

    static QString enumBaseClass(const AbstractMetaEnum &e);

protected:
    static QString getDocumentation(const XQueryPtr &xquery,
                                    const QString &query,
                                    const DocModificationList &mods);

    static AbstractMetaFunctionCList documentableFunctions(const AbstractMetaClassCPtr &metaClass);

    static QString applyDocModifications(const DocModificationList &mods, const QString &xml);

private:
    QString m_packageName;
    QString m_docDataDir;
    QString m_libSourceDir;

    static QString execXQuery(const XQueryPtr &xquery, const QString &query) ;
};

#endif // DOCPARSER_H
