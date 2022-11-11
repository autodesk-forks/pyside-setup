import groovy.json.*
@Library("PSL") _

properties([
  disableConcurrentBuilds(),
  parameters([
    string(name: 'COMMIT', defaultValue: "", description: 'Commit ID to build from (optional)'),
    choice(name: 'QtVersion', choices:['match', '6.4.0', '6.2.3', '5.15.2'], description: 'Qt version (format: A.B.C). \'match\' means use Qt matching PySide6 version'),
    string(name: 'QtBuildID', defaultValue: 'latest', description: 'Qt Build ID on Artifactory (format: AAAA-MM-DD-hh-mm)'),
    choice(name: 'PythonVersion', choices:['3.10.6', '3.9.7'], description: 'Python version (format: A.B.C)'),
  ])
])

def currentStage = ""
changeSetContent = ""
gitCommitUser = ""
gitCommitShort = ""
artifactName = ""
artifactProps = ""

workspaceRoot = [:]
PysidePackage = [:]
artifacts = [:]
results = [:]
hostName = [:]

downloadDir = 'external_dependencies' // Contains the artifacts from artifactory
buildType = "DI"    // Only build DI package - Should have another pipeline for CI that triggers on new changes and DI on schedule.  DI build should build on last successful CI
config = "Release"  // We always build Release for this package.  Set build parameter to select Debug/Release in case we need to support both
gitCommit = ""

artifactoryRoot = "https://art-bobcat.autodesk.com/artifactory/"
def now = new Date()
buildTime = String.format('%tY-%<tm-%<td-%<tH-%<tM', now)
buildID = buildTime.replace("-", "")
product = "pyside"
gitBranch = env.BRANCH_NAME  // Actual branch name in GIT repo
pysideVersion = "" // This is initialized in Initialize.

// PythonVersion: Extract MAJOR(A), MINOR(B), and REVISION(C)
pythonVersionArray = params.PythonVersion.tokenize(".")
pythonVersionA = pythonVersionArray[0]
pythonVersionB = pythonVersionArray[1]
pythonVersionAdotB = "${pythonVersionA}.${pythonVersionB}"

// Email Notifications - List of Recipients
default_Recipients = ["Bang.Nguyen@autodesk.com"]
DEVTeam_Recipients = ["marc-andre.brodeur@autodesk.com"]
ENGOPSTeam_Recipients = ["Bang.Nguyen@autodesk.com", "vishal.dalal@autodesk.com"]
QtTeam_Recipients = ["Daniela.Stajic@autodesk.com", "Wayne.Arnold@autodesk.com", "Richard.Langlois@autodesk.com", "william.smith@autodesk.com", "Bang.Nguyen@autodesk.com"]

buildStages = [
    "Initialize":[name:'Initialize', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
    "Setup":[name:'Setup', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
    "Sync":[name:'Sync', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
    "Build":[name:'Build', emailTO: (DEVTeam_Recipients + default_Recipients).join(", ")],
    "Package":[name:'Package', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
    "Publish":[name:'Publish', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
    "Finalize":[name:'Finalize', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
]

buildConfigs = [
    "pyside_local": "local",
    "pyside_Rhel8": "Rhel 8.6",
    "pyside_Mac": "Monterey 12.4.0",
    "pyside_Win": "Windows 10"
]

//-----------------------------------------------------------------------------
def getPysideVersion(srcDir) {
    def scriptDir = "${srcDir}/autodesk-maya-scripts"
    def ver = sh (
        script: "python ${scriptDir}/fetch-qt-version.py ${srcDir}",
        returnStdout: true
    ).trim()

    // If for some reason, a version number couldn't be found, we will go back
    // to the prior logic of using "Preflight" for the version.
    ver = ver ? ver : "Preflight"
    println "pysideVersion: ${ver}\n"
    return ver
}

//-----------------------------------------------------------------------------
def checkOS() {
    if (isUnix()) {
        def uname = sh script: 'uname', returnStdout: true
        if (uname.startsWith("Darwin")) {
            return "Mac"
        }
        else {
            def distro = sh script: "hostnamectl | awk '/Operating System/ { print \$3 }'", returnStdout: true
            print "distro: ${distro}"
            if (distro.contains("CentOS")) {
               return "Linux"
            } else {
               return "RedHat"
            }
        }
    }
    else {
        return "Windows"
    }
}

//-----------------------------------------------------------------------------
def getHostName() {
    def hostName = ""
    if (isUnix()) {
        hostName = sh (
            script: "hostname",
            returnStdout: true
        ).trim()
    }
    else {
        hostName = bat (
            script: "@hostname",
            returnStdout: true
        ).trim()
    }
    return hostName
}

//-----------------------------------------------------------------------------
def notifyBuild(buildStatus, String gitBranch) {
    // build status of null means successful
    buildStatus =  buildStatus ?: 'SUCCESSFUL'
    assert pysideVersion != ""

    // Default values
    def subject = "[${product}_${pysideVersion}] - ${buildStatus}: Job - '${gitBranch} [${env.BUILD_NUMBER}]'"
    def emailTO
    def color

    if (buildStatus == "FAILURE") {
        color = "#ff0000;"
    } else if (buildStatus == "SUCCESSFUL") {
        color = "#008000;"
    } else {
        color = "#ffae42;"
    }

    println "Build Result: ${buildStatus}\n"
    if (buildStatus == "SUCCESSFUL") {
        emailTO = QtTeam_Recipients.join(", ")
    }
    else if (buildStatus == "ABORTED" || buildStatus == "UNSTABLE") {
        emailTO = default_Recipients.join(", ")
    }
    else {
        def failedStage = getFailedStage(results)
        emailTO = buildStages[failedStage].emailTO
    }

    // Override all email notifications by sending to this email address instead of the list of recipients
    emailTO = "marc-andre.brodeur@autodesk.com"

    def buildLocation = buildStatus == "SUCCESSFUL" ? getBuildLocation() : ""
    def buildResult = getBuildResult(results, buildConfigs)
    def details = """
     <html>
        <body><table cellpadding="10">
            <tr><td>Outcome</td><td><span style=\"color: ${color}\"><strong>${buildStatus}</strong></span></td></tr>
            <tr><td>Build URL</td><td><a href="${env.BUILD_URL}">${gitBranch} [${env.BUILD_NUMBER}]</a></td></tr>
            <tr valign="top"><td>Commit(s)</td><td><span style="white-space: pre-line">${changeSetContent}</span></td></tr>
            <tr><td>Results</td><td><table col align="left" cellspacing="6">${buildResult}</table></td></tr>
            <tr>${buildLocation}</tr>
        </table></body>
     </html>"""

 emailext(
      mimeType: 'text/html',
      subject: subject,
      from: 'engops.team.tesla@autodesk.com',
      body: details,
      to: emailTO,
      recipientProviders: [[$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']]
    )
}

//-----------------------------------------------------------------------------
def getChangeSetString(String commitInfo) {
    def changes = ""
    def count = 0
    def outputString = ""
    def commit = ""
    def message = ""

    def jsonSlurper = new JsonSlurper()
    def object = jsonSlurper.parseText(commitInfo)

    count = object.data.size()
    commitCleanString = object.CleanDirective
    object.data.each {
        commit = it.Commit.take(8)
        message = it.Message
        if (message.length() > 60) {
            message = message.take(60) + "..."
        }
        changes += "&emsp;<span style='color:#6fb9dc;'>${commit}</span> by ${it.Author} - <span style='color:#feba29;'>${message}</span><br>"
    }

    if (count == 0) {
        outputString = "There are no change in this build."
    }
    else {
        outputString = "Total: ${count}<br>"
        outputString += changes
    }
    return outputString
}

//-----------------------------------------------------------------------------
@NonCPS
def matchPysideVersion(String version) {
    def matches = (version =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3})(?:\.(\d{1,3}))?([ab]\d)?$/)
    if (matches) {
        def major_minor_patch = matches[0][1]
        def revision = matches[0][2]
        def prerelease = matches[0][3]
        return [major_minor_patch, revision, prerelease]
    } else {
        return null
    }
}

def getQtVersion(String qtVer, String artifactoryURL) {
    def versionComponents
    if (qtVer == 'match') {
        versionComponents = matchPysideVersion(pysideVersion)
        if (versionComponents) {
            def major_minor_patch = versionComponents[0]
            def revision = versionComponents[1]
            def prerelease = versionComponents[2]
            println("pysideVersion: " + major_minor_patch + ", " + revision + ", " + prerelease)
            qtVer = major_minor_patch
        } else {
            error("**** Error:  pysideVersion is in an unexpected format. Expecting #.#.#(.#)? ***** ")
            return ""
        }
    }

    def response = sh (
        script: "curl -s -X GET ${artifactoryURL}",
        returnStdout: true
    ).trim()
    def info = readJSON text: response
    def repo = info.repo
    def path = info.path
    def qtVersionList = info.children
    def qtVersionTriplet = ""
    def qtVersionURL
    def qtVersionFound = ""

    def versions = qtVersionList.findAll({ item -> item.folder }).collect { item -> item.uri.substring(1) }
    def command = """sort -r -V - << EOF
${versions.join("\n")}
EOF"""
    def sortedVersions = sh (
        script: command,
        returnStdout: true
    ).trim()
    versions = sortedVersions.split()

    print("sorted Qt versions: " + versions)

    for (version in versions) {
        versionTriplet = ""
        versionComponents = matchPysideVersion(version)
        if (versionComponents) {
            def major_minor_patch = versionComponents[0]
            def revision = versionComponents[1]
            def prerelease = versionComponents[2]
            println("Checking version: " + major_minor_patch + ", " + revision + ", " + prerelease)
            versionTriplet = major_minor_patch
        } else {
            print("**** Warning: Skipping invalid pyside version ${version}. Expecting format of #.#.#(.#)? ***** ")
        }

        qtVersionURL = artifactoryURL + "/" + versionTriplet + "/Maya"
        if (qtVer == versionTriplet) {
            response = sh (
                script: "curl -s -X GET ${qtVersionURL}",
                returnStdout: true
            ).trim()
            info = readJSON text: response
            def buildIDList = info.children
            if (buildIDList && buildIDList.size() > 0) {
                for (buildIDDir in buildIDList) {
                    if (buildIDDir.folder) {
                        qtVersionFound = version
                        break
                    }
                }
            }
        }
        if (qtVersionFound) {
            break
        }
    }
    return qtVersionFound
}

//-----------------------------------------------------------------------------
def GetArtifacts(String workDir, String buildConfig) {
    def artifactDownload = new ors.utils.common_artifactory(steps, env, Artifactory, 'svc-p-mayaoss')

    dir(workDir) {
        for (artifact in artifacts[buildConfig]) {
            def downloadspec = """{
                "files": [
                    {
                        "pattern": "${artifact}",
                        "target": "${downloadDir}/"
                    }
                ]
            }"""

            print "Download Spec: ${downloadspec}"
            artifactDownload.download(artifactoryRoot, downloadspec)

            index = artifact.indexOf('/')
            print "index: ${index}"
            def downloadFile = downloadDir + artifact.substring(index)
            print "downloadFile: ${downloadFile}"
            print "${downloadFile} --- ${downloadDir}"

            if (isUnix()) {
                // tar.gz is the default, but some artifacts may be .tar.xz, and some may be .zip
                z = "z"
                if (downloadFile.endsWith(".tar.gz") || downloadFile.endsWith(".tar.xz")) {
                    // 'J' option to tar expands .xz files
                    z = downloadFile.endsWith(".tar.xz") ? "J" : "z"
                    runOSCommand("tar ${z}xvf ${downloadFile} -C ${downloadDir}")
                } else if (downloadFile.endsWith(".zip")) {
                    runOSCommand("unzip ${downloadFile} -d ${downloadDir}")
                }
            }
            else {
                runOSCommand("7z e ${downloadFile} -y -spf -o${downloadDir}")
            }
        }
    }
}

//-----------------------------------------------------------------------------
def getBuildLocation() {
    def outputString = ""
    outputString = "<td>Artifacts</td><td>"
    buildConfigs.each {
        if (it.value != "local") {
            outputString += "${artifactoryRoot}${artifactoryTarget}${PysidePackage[it.key]}<br>"
        }
    }
    outputString += "</td>"
    return outputString
}

//-----------------------------------------------------------------------------
def getBuildResult(Map results, Map buildConfigs) {
    def buildResult = ""
    //Stages Name
    results.eachWithIndex { configs, stages, i ->
        if (i == 0) {
            buildResult += '<tr><th></th>'
            stages.each {
                buildResult += '<th>' + it.key + '</th>'
            }
            buildResult += '</tr>'
        }
    }
    //Stage outcome for each build config
    results.each { configs, stages ->
        buildResult += '<tr align="center"><td><b>' + buildConfigs[configs] + "</b><br>(${hostName[configs]})" + '</td>'
        stages.each {
            if (it.value == "") {
                buildResult += "<td></td>"
            }
            else {
                if (it.value == "Error") {
                    buildResult += '<td><span style="color:#ff0000;">' + "\u2717" + '</span></td>'
                }
                else if (it.value == "Warning") {
                    buildResult += '<td><span style="color:#ffae42;">' + "\u26A0" + '</span></td>'
                }
                else if (it.value == "Timeout") {
                    buildResult += '<td><span style="color:#ff0000;">' + "\u29B2" + '</span></td>'
                }
                else if (it.value == "Aborted") {
                    buildResult += '<td><span style="color:#ff0000;">' + "\u2014" + '</span></td>'
                }
                else if (it.value == "Skip") {
                    buildResult += '<td><span style="color:#ff0000;">' + "Skip" + '</span></td>'
                }
                else { //Pass
                    buildResult += '<td><span style="color:#00ff00;">' + "\u2713" + '</span></td>'
                }
            }
        }
        buildResult += '</tr>'
    }
    return buildResult
}

//-----------------------------------------------------------------------------
def getFailedStage(Map results) {
    def failedStage = ""
    results.each { configs, stages ->
        stages.each {
            if (it.value == "Error" || it.value == "Timeout") {
                failedStage = it.key
            }
        }
    }
    return failedStage
}
//-----------------------------------------------------------------------------

def errorHandler(Exception e, String buildConfig="", String stage="") {

    if (e instanceof org.jenkinsci.plugins.workflow.steps.FlowInterruptedException || e instanceof java.lang.InterruptedException) {
        println "errorHandler: FlowInterruptedException ${e}"
        def actions = currentBuild.getRawBuild().getActions(jenkins.model.InterruptedBuildAction)
        println ("Actions = ${actions}")
        if (!actions.isEmpty()) {
            print "User Abort"
            currentBuild.result = "ABORTED"
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Aborted"
                throw e
            }
        } else {
            print "Project Timeout!"
            currentBuild.result = "FAILURE"
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Timeout"
                throw e
            }
        }
    } else if (e instanceof hudson.AbortException) {
        println "errorHandler: AbortException ${e}"
        def actions = currentBuild.getRawBuild().getActions(jenkins.model.InterruptedBuildAction)
        println ("Actions = ${actions}")
        // this ambiguous condition means during a shell step, user probably aborted
        if (!actions.isEmpty()) {
            print "AbortException: User Abort"
            currentBuild.result = 'ABORTED'
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Aborted"
                throw e
            }
        } else {
            print "AbortException: Error"
            currentBuild.result = 'FAILURE'
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Error"
                throw e
            }
        }
    } else {
        if (e.toString().contains("Ignored Errors")) {
            currentBuild.result = 'UNSTABLE'
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Warning"
            }
        } else {
            println "errorHandler: Unhandled Error: ${e}"
            currentBuild.result = 'FAILURE'
            if (buildConfig != "" && stage != "") {
                results[buildConfig][stage] = "Error"
                throw e
            }
        }
    }
}

//-----------------------------------------------------------------------------
def getWorkspace(String buildConfig) {
    def root = pwd()
    def index1 = root.lastIndexOf('\\')
    def index2 = root.lastIndexOf('/')
    def count = (index1 > index2 ? index1 : index2) + 1
    def workDir

    if (buildConfig.toLowerCase().contains('_local')) {
        workDir = root.take(count) + product
    }
    else {
        //Use same workspace for all release branches
        workDir = root.take(count) + product + '_maya'
    }
    println "workDir: ${workDir}"
    return workDir
}

// Execute native shell command as per OS
//-----------------------------------------------------------------------------
def runOSCommand(String cmd, errorHandler='abort') {
    try {
        if (isUnix()) {
            sh cmd
        } else {
            bat cmd
        }
    } catch(failure) {
        if (errorHandler.equalsIgnoreCase('ignore')) {
            throw new RuntimeException("Ignored Errors") //Ignore error and will set overall build status to 'UNSTABLE'
        }
        else {
            throw failure
        }
    }
}

//-----------------------------------------------------------------------------
def getQtArtifacts(String buildID, String artifactoryURL) {
        def response = sh (
            script: "curl -s -X GET ${artifactoryURL}",
            returnStdout: true
        ).trim()
        def info = readJSON text: response
        def repo = info.repo
        def path = info.path
        def dateFolders = info.children.findAll({ item -> item.folder }).collect { item -> item.uri.substring(1) }
        // Sort numerically since they are in YYYY-mm-dd-HH-MM format and will sort correctly by numeric sort.
        def command = """sort -r -n - << EOF
${dateFolders.join("\n")}
EOF"""
        def sortedDateFolders = sh (
            script: command,
            returnStdout: true
        ).trim()
        dateFolders = sortedDateFolders.split()
        println "sorted dateFolders: ${dateFolders}"

        def qtArtifactWin = ""
        def qtArtifactMac = ""
        def qtArtifactRhel8 = ""
        for (dateFolder in dateFolders) {
            if (buildID != 'latest' && !dateFolder.contains(buildID))
                continue
            buildURL = artifactoryURL + "/" + dateFolder
            response = sh (
                script: "curl -s -X GET ${buildURL}",
                returnStdout: true
            ).trim()
            info = readJSON text: response
            def artifactList = info.children

            // There must be somewhere between 3 and 5 entries in the folder
            // mac, linux, windows as a minimum. Some builds have a second windows
            // artifact splitting out the examples, and some also have two linux
            // builds - RHEL8 and CentOS 7.
            if (artifactList.size() < 3 || artifactList.size() > 5)
                continue // Try the next one

            if (buildID == 'latest' || dateFolder.contains(buildID)) {
                artifactList.each {
                    if (it.uri.contains('Maya-Qt-Windows')) {
                        qtArtifactWin = info.repo + info.path + it.uri
                    } else if (it.uri.contains('Maya-Qt-Rhel8')) {
                        qtArtifactRhel8 = info.repo + info.path + it.uri
                    } else if (it.uri.contains('Maya-Qt-Mac')) {
                        qtArtifactMac = info.repo + info.path + it.uri
                    }
                }
                break
            }
        }

        return [qtArtifactWin, qtArtifactRhel8, qtArtifactMac]
}

//-----------------------------------------------------------------------------
def Initialize(String buildConfig) {
    def stage = "Initialize"

    try {
        def workDir = getWorkspace(buildConfig)
        def srcDir = "${workDir}/src"
        def jenkinsScriptDir = "${workDir}/src/autodesk-maya-jenkins-helpers-internal"

        dir(srcDir) {
            scmInfo = checkout scm
            gitCommit = params.COMMIT == "" ? scmInfo.GIT_COMMIT : params.COMMIT
            println "${scm.branches} Branch: ${env.BRANCH_NAME}"
            runOSCommand("git checkout HEAD~")
            runOSCommand("git branch -D ${env.BRANCH_NAME}")
            runOSCommand("git fetch")
            runOSCommand("git checkout ${env.BRANCH_NAME}")

            pysideVersion = getPysideVersion(srcDir)
            println "pysideVersion: ${pysideVersion}"
            assert pysideVersion != ""

            gitCommitShort = gitCommit.substring(0,8)
            if (pysideVersion == 'Preflight') {
                gitCommitUser = sh (
                    script: "git show -s --format='%an' ${gitCommit} | awk '{print \$1\$2}' ",
                    returnStdout: true
                ).trim()
                println "Commit User: ${gitCommitUser}"
                lastBuildCommit = gitCommit
                lastSuccessfulCommit = gitCommit
                artifactName = String.format("%s-%s-%s", gitCommitUser, buildID, gitCommitShort)
                artifactProps = "RetentionPolicy=7"
            } else {
                //Get lastBuildCommit & lastSuccessfulCommit
                buildInfo = sh (
                    script: "python $jenkinsScriptDir/updatebuildcommit.py -g -p ${product} -b ${pysideVersion} -t ${buildType} -c ${config}",
                    returnStdout: true
                ).trim()
                (lastSuccessfulCommit, lastBuildCommit) = buildInfo.tokenize( ' ' )
                print "Last Successful Commit: ${lastSuccessfulCommit} -- Last Build Commit: ${lastBuildCommit}"

                if (lastSuccessfulCommit == null) {
                    lastSuccessfulCommit = gitCommit
                }
                if (lastBuildCommit == null) {
                    lastBuildCommit = gitCommit
                }
                artifactName = String.format("%s-%s", buildID, gitCommitShort)
            }

            commitInfo = sh (
                script: "python $jenkinsScriptDir/getcommitinfo.py -s ${srcDir} -sc ${lastSuccessfulCommit} -bc ${lastBuildCommit} -gc ${gitCommit}",
                returnStdout: true
            ).trim()
            print "CommitInfo: ${commitInfo}"
            changeSetContent = getChangeSetString(commitInfo)
        }

        qtVersion = getQtVersion(params.QtVersion, "${artifactoryRoot}api/storage/oss-stg-generic/Qt")

        println("qtVersion: ${qtVersion}")
        if (qtVersion == "") {
            error("**** Error:  Unable to find version of Qt that contains artifacts for Maya build ***** ")
        }

        // Define where to publish PySide6 on Artifactory
        artifactoryTarget = "oss-stg-generic/pyside6/${pysideVersion}/Maya/Qt${qtVersion}/Python${pythonVersionAdotB}/${buildTime}/"

        (QtArtifact_Win, QtArtifact_Rhel8, QtArtifact_Mac) = getQtArtifacts(params.QtBuildID, "${artifactoryRoot}api/storage/oss-stg-generic/Qt/${qtVersion}/Maya")
        println("Win: ${QtArtifact_Win}, Rhel8: ${QtArtifact_Rhel8}, Mac: ${QtArtifact_Mac}")

        if (QtArtifact_Win == "" || QtArtifact_Rhel8 == "" || QtArtifact_Mac == "") {
            error("**** Error:  Unable to find specified Qt artifact ***** ")
        }

        workspaceRoot[buildConfig] = workDir
        hostName[buildConfig] = getHostName()

        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Setup(String buildConfig) {
    def stage = "Setup"
    env.PYSIDEVERSION = "${pysideVersion}"
    env.QTVERSION = "${qtVersion}"
    env.PYTHONVERSION = "${params.PythonVersion}"

    try {
        def workDir = getWorkspace(buildConfig)
        ws(workDir) {
            // Delete 'build', 'install' and 'external_dependencies' folders before build
            dir ('build') {
                deleteDir()
            }
            dir ('install') {
                deleteDir()
            }
            dir ('external_dependencies') {
                deleteDir()
            }
        }
        workspaceRoot[buildConfig] = workDir
        hostName[buildConfig] = getHostName()

        if (checkOS() == "Mac") {
            PysidePackage[buildConfig] = "${artifactName}-Maya-PySide6-Mac.tar.gz"
            artifacts[buildConfig]  = ["${QtArtifact_Mac}", "team-maya-generic/libclang/release_140-based/libclang-release_140-based-macos-universal.tar.gz"]
            if (params.PythonVersion == '3.10.6') {
                artifacts[buildConfig] += "team-maya-generic/python/3.10.6/cpython-3.10.6-mac-universal2-expandedframework-MANUAL-2022_09_22_1000.tar.gz"
            } else if (params.PythonVersion == '3.9.7') {
                artifacts[buildConfig] += "team-maya-generic/python/3.9.7/cpython-3.9.7-mac-002-universal2-expandedframework.tar.gz"
            }
        }
        else if (checkOS() == "RedHat") {
            PysidePackage[buildConfig] = "${artifactName}-Maya-PySide6-Rhel8.tar.gz"
            artifacts[buildConfig]  = ["${QtArtifact_Rhel8}", "team-maya-generic/libclang/release_140-based/libclang-release_140-based-linux-Rhel8.2-gcc9.2-x86_64.tar.gz", "team-maya-generic/Cmake/cmake-3.22.1-linux-x86_64.tar.gz"]
            if (params.PythonVersion == '3.10.6') {
                artifacts[buildConfig] += "team-maya-generic/python/3.10.6/cpython-3.10.6-gcc-11.2.1-system_openssl-1.1.1k_MANUAL_202210211108.zip"
            } else if (params.PythonVersion == '3.9.7') {
                artifacts[buildConfig] += "team-maya-generic/python/3.9.7/cpython-3.9.7-gcc-9.3.1-openssl-1.1.1k_manual_build-2.tar.gz"
            }
        }
        else {
            PysidePackage[buildConfig] = "${artifactName}-Maya-PySide6-Windows.zip"
            artifacts[buildConfig]  = ["${QtArtifact_Win}", "team-maya-generic/libclang/release_140-based/libclang-release_140-based-windows-vs2019_64.zip", "team-maya-generic/openssl/1.1.1g/openssl-1.1.1g-win-vc140.zip", "team-maya-generic/Cmake/cmake-3.22.1-windows-x86_64.zip", "team-shotgun-view-master-generic/jom/jom_1_1_3.zip"]
            if (params.PythonVersion == '3.10.6') {
                artifacts[buildConfig] += "team-maya-generic/python/3.10.6/cpython-3.10.6-win-MANUAL-2022_08_31_1430.zip"
            } else if (params.PythonVersion == '3.9.7') {
                artifacts[buildConfig] += "team-maya-generic/python/3.9.7/cpython-3.9.7-win-001.zip"
            }
        }
        print "$buildConfig artifacts: ${artifacts[buildConfig]}"

        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Sync(String workDir, String buildConfig) {
    def stage = "Sync"

    try {
        def srcDir = "${workDir}/src"
        print "--- Sync ---"
        dir(srcDir) {
            def exists = fileExists(".git")
            if (!exists) {
                withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'svc_p_mescm', usernameVariable: 'GITUSER', passwordVariable: 'GITPWD']]) {
                    runOSCommand "git clone --branch ${gitBranch} https://${GITUSER}:\"${GITPWD}\"@git.autodesk.com/autodesk-forks/pyside-setup.git . "
                }
            }
            print "Commit: $gitCommit"
            //checkout scm to the commit_id

            checkout([$class: 'GitSCM', branches: [[name: gitCommit ]],
                userRemoteConfigs: scm.userRemoteConfigs])

            // Remove all private files first
            runOSCommand("git submodule foreach --recursive \"git clean -dfx\" && git clean -dfx")
        }

        print "--- Download Packages ---"
        GetArtifacts(workDir, buildConfig)

        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}


//-----------------------------------------------------------------------------
def Build(String workDir, String buildConfig) {
    def stage = "Build"
    def flavor = buildConfig.substring(0, buildConfig.lastIndexOf("_")) // We may need this to invoke different build flavors i.e. Maya/MayaLT/MayaIO
    def buildDir = "${workDir}/build"
    def srcDir = "${workDir}/src"
    def scriptDir = "${workDir}/src/autodesk-maya-scripts"

    if (isUnix()){
        runOSCommand("echo ${buildConfig} PythonVersion: $PYTHONVERSION Pyside: $PYSIDEVERSION Qt: $QTVERSION")
    }
    else {
        runOSCommand("echo ${buildConfig} PythonVersion: %PYTHONVERSION% Pyside: %PYSIDEVERSION% Qt: %QTVERSION%")
    }

    try {
        assert pysideVersion != ""
        dir (srcDir) {
            def cpythonDir = "${workDir}/${downloadDir}/cpython"
            if (checkOS() == "Mac") {
                if (pythonVersionAdotB == '3.9') {
                    runOSCommand('brew link --overwrite --force python@3.9')
                }
                env.PYTHONEXE = "${cpythonDir}/${params.PythonVersion}/RelWithdebInfo/bin/python" // Note lowercase d debInfo
                runOSCommand("find ${cpythonDir} -not -perm -200 -exec chmod u+w {} \\;")
                runOSCommand("xattr -r -d com.apple.quarantine ${cpythonDir}") // Remove quarantine so the interpreter will actually run.
                runOSCommand('xcodebuild -version && xcodebuild -showsdks')
                runOSCommand("""PYTHONEXE=${env.PYTHONEXE} PYTHONVERSION=${params.PythonVersion} PYSIDEVERSION=${pysideVersion} QTVERSION=${qtVersion} $scriptDir/adsk_maya_build_pyside6_osx.sh ${workDir}""")
            }
            else if (checkOS() == "Linux" || checkOS() == "RedHat") {
                def gccToolset = (checkOS() == "Linux") ? "devtoolset-9" : "gcc-toolset-11"
                env.PYTHONEXE = "${cpythonDir}/${params.PythonVersion}/RelWithDebInfo/bin/python${pythonVersionAdotB}"
                env.PYTHONDEXE = "${cpythonDir}/${params.PythonVersion}/Debug/bin/python${pythonVersionAdotB}"
                runOSCommand("scl enable ${gccToolset} 'PYTHONEXE=${env.PYTHONEXE} PYTHONDEXE=${env.PYTHONDEXE} PYTHONVERSION=${params.PythonVersion} PYSIDEVERSION=${pysideVersion} QTVERSION=${qtVersion} bash $scriptDir/adsk_maya_build_pyside6_lnx.sh ${workDir}'")
            }
            else {
                env.PYTHONEXE = "${cpythonDir}/${params.PythonVersion}/RelWithdebInfo/python.exe"
                env.PYTHONDEXE = "${cpythonDir}/${params.PythonVersion}/Debug/python_d.exe"
                runOSCommand("""$scriptDir\\adsk_maya_build_pyside6_win.bat ${workDir}""")
            }
        }
        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Package(String workDir, String buildConfig) {
    def stage = "Package"
    try {
        assert pysideVersion != ""
        def srcDir = "${workDir}/src"
        def scriptDir = "${workDir}/src/autodesk-maya-scripts"
        dir (srcDir) {
            if (checkOS() == "Mac") {
                runOSCommand("""PYTHONVERSION=${params.PythonVersion} PYSIDEVERSION=${pysideVersion} QTVERSION=${qtVersion} $scriptDir/adsk_maya_package_pyside6_osx.sh ${workDir}""")
            }
            else if (checkOS() == "Linux" || checkOS() == "RedHat") {
                runOSCommand("""PYTHONVERSION=${params.PythonVersion} PYSIDEVERSION=${pysideVersion} QTVERSION=${qtVersion} $scriptDir/adsk_maya_package_pyside6_lnx.sh ${workDir}""")
            }
            else {
                runOSCommand("""$scriptDir\\adsk_maya_package_pyside6_win.bat ${workDir}""")
            }
        }

        dir(workDir) {
            // Clean up prior build archives just before creating the new ones.
            dir ('out') {
                deleteDir()
            }

            dir('install') {
                if (isUnix()){
                    runOSCommand("""mkdir ../out""")  //Create 'out' folder where zip files will be created.
                    runOSCommand("""tar -czf ../out/${PysidePackage[buildConfig]} *""")
                } else {
                    runOSCommand("""7z a -tzip ../out/${PysidePackage[buildConfig]} *""")
                }
            }
        }
        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

// Uploading of packages to artifactory
///////////////////////////////////////////////////////////////////////////////////////////////////////

def Publish(String workDir, String buildConfig) {
    def stage = "Publish"
    def pattern
    def props
    try {
        dir(workDir) {
            // Temporarily use svc_p_mescm instead of svc-p-mayaoss account as
            // the latter seems to not have permissions to publish anymore.
            artifactUpload = new ors.utils.common_artifactory(steps, env, Artifactory, 'svc-p-mescm')

            if (checkOS() == "Mac") {
                pattern = "out/*.tar.gz"
                props = "QtArtifact=${QtArtifact_Mac};commit=${gitCommit};OS=OSX12.4.0;Compiler=xcode13.4.1;libclang=release_140-based"
                if (artifactProps != "") {
                    props = String.format("%s;%s", props, artifactProps)
                }
            }
            else if (checkOS() == "RedHat") {
                pattern = "out/*.tar.gz"
                props = "QtArtifact=${QtArtifact_Rhel8};commit=${gitCommit};OS=Rhel8.6;Compiler=gcc11.2.1;libclang=release_140-based"
                if (artifactProps != "") {
                    props = String.format("%s;%s", props, artifactProps)
                }
            }
            else {
                pattern = "out/*.zip"
                props = "QtArtifact=${QtArtifact_Win};commit=${gitCommit};OS=Windows10;Compiler=MSVC-14.33.31629;libclang=release_140-based"
                if (artifactProps != "") {
                    props = String.format("%s;%s", props, artifactProps)
                }
            }
            def uploadSpec = """{
                "files": [
                    {
                        "pattern": "${pattern}",
                        "target": "${artifactoryTarget}",
                        "recursive": "false",
                        "props": "${props}"
                    }
                ]
            }"""

            artifactUpload.upload(artifactoryRoot, uploadSpec)

            // Workaround for Jenkins Bug:
            // Sometimes, Jenkins can't remove the external_dependencies/ directory (artifactory) in the Setup phase on Windows.
            // Instead, we delete the folder using after publishing the artifact using an OS command
            if (checkOS() == "Windows") {
                runOSCommand("rmdir /s /q ${downloadDir}")
            }
        }
        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Finalize(String buildConfig) {
    def stage = "Finalize"
    try {
        assert pysideVersion != ""
        if (pysideVersion != 'Preflight') {
            def workDir = getWorkspace(buildConfig)
            def srcDir = "${workDir}/src"
            def jenkinsScriptDir = "${workDir}/src/autodesk-maya-jenkins-helpers-internal"

            dir(srcDir) {
                if (currentBuild.result == "FAILURE") {
                    runOSCommand("python $jenkinsScriptDir/updatebuildcommit.py -s -p ${product} -b ${pysideVersion} -t ${buildType} -c ${config} -sc ${lastSuccessfulCommit} -bc ${gitCommit}")
                } else {
                    runOSCommand("python $jenkinsScriptDir/updatebuildcommit.py -s -p ${product} -b ${pysideVersion} -t ${buildType} -c ${config} -sc ${gitCommit} -bc ${gitCommit}")
                }
            }
        }
        results[buildConfig][stage] = "Success"
    } catch (e) {
        errorHandler(e, buildConfig, stage)
    }
}

// Calling of parallel steps
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------

// Define which node to use for each platform
def generateSteps = {pyside_rhel8, pyside_mac, pyside_win ->
    return [
        "pyside_Rhel8" : { node("qt-2024-linux-rhel8-nogpu-pool") { pyside_rhel8() }},
        "pyside_Mac" : { node("OSS-Maya-OSX12.4.0-Xcode13.3") { pyside_mac() }},
        "pyside_Win" : { node("OSS-Maya_2024_Win10-vs2022_qt6_build") { pyside_win() }}
        ]
}

// Initialize result matrix based on buildConfigs & stages
buildStages.each { stageKey, stageVal ->
    def stage = stageVal.name
    buildConfigs.each {
        if(results.containsKey(it.key))
        {
            results.get(it.key).putAll([(stage):''])
        }
        else
        {
            results.put(it.key, [(stage):''])
        }
    }
}

try {
    node('pyside_local'){
        stage (buildStages['Initialize'].name)
        {
            Initialize('pyside_local')
        }
    }

    stage (buildStages['Setup'].name)
    {
        parallel generateSteps(
            {
                Setup('pyside_Rhel8')
            },
            {
                Setup('pyside_Mac')
            },
            {
                Setup('pyside_Win')
            }
        )
    }

    stage (buildStages['Sync'].name)
    {
        parallel generateSteps(
            {
                Sync(workspaceRoot['pyside_Rhel8'], 'pyside_Rhel8')
            },
            {
                Sync(workspaceRoot['pyside_Mac'], 'pyside_Mac')
            },
            {
                Sync(workspaceRoot['pyside_Win'], 'pyside_Win')
            }
        )
    }

    stage (buildStages['Build'].name)
    {
        parallel generateSteps(
            {
                Build(workspaceRoot['pyside_Rhel8'], 'pyside_Rhel8')
            },
            {
                Build(workspaceRoot['pyside_Mac'], 'pyside_Mac')
            },
            {
                Build(workspaceRoot['pyside_Win'], 'pyside_Win')
            }
        )
    }

    stage (buildStages['Package'].name)
    {
        parallel generateSteps(
            {
                Package(workspaceRoot['pyside_Rhel8'], 'pyside_Rhel8')
            },
            {
                Package(workspaceRoot['pyside_Mac'], 'pyside_Mac')
            },
            {
                Package(workspaceRoot['pyside_Win'], 'pyside_Win')
            }
        )
    }

    stage (buildStages['Publish'].name)
    {
        parallel generateSteps(
            {
                Publish(workspaceRoot['pyside_Rhel8'], 'pyside_Rhel8')
            },
            {
                Publish(workspaceRoot['pyside_Mac'], 'pyside_Mac')
            },
            {
                Publish(workspaceRoot['pyside_Win'], 'pyside_Win')
            }
        )
    }

    node('pyside_local'){
        stage (buildStages['Finalize'].name)
        {
            Finalize('pyside_local')
        }
    }
    assert pysideVersion != ""
} catch (e) {
    errorHandler(e)
} finally {
    notifyBuild(currentBuild.result, gitBranch)
}
