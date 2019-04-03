import groovy.json.*
@Library("PSL") _

properties([
  disableConcurrentBuilds(),
  parameters([
	string(defaultValue: "", description: 'Commit', name: 'COMMIT'),
	string(name: 'QTVersion', defaultValue: '5.12.2'),
	string(name: 'QTBuildID', defaultValue: '8'),
  ])
])

def currentStage = ""
changeSetContent = ""

workspaceRoot = [:]
PysidePackage = [:]
artifacts = [:]
results = [:]
hostName = [:]

downloadDir = 'artifactory'
buildType = "DI"    // Only build DI package - Should have another pipeline for CI that triggers on new changes and DI on schedule.  DI build should build on last successful CI
config = "Release"  //We always build Release for this package.  Set build parameter to select Debug/Release in case we need to support both
gitCommit = ""

product = "pyside"
branch = "5.12.2" //Pyside branch version
pysideVersion = "${product}_${branch}" //Sub-folder name in zip/tar files
qtVersion = "qt_${params.QTVersion}"
gitBranch = env.BRANCH_NAME  //Actual branch name in GIT repo

default_Recipients = ["Bang.Nguyen@autodesk.com"]
DEVTeam_Recipients = ["keith.kyzivat@autodesk.com"]
ENGOPSTeam_Recipients = ["Bang.Nguyen@autodesk.com", "vishal.dalal@autodesk.com"]
QTTeam_Recipients = ["Daniela.Stajic@autodesk.com", "Wayne.Arnold@autodesk.com", "Richard.Langlois@autodesk.com", "william.smith@autodesk.com"]


buildStages = [
	 "Initialize":[name:'Initialize', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
	 "Setup":[name:'Setup', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
     "Sync":[name:'Sync', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
	 "Build":[name:'Build', emailTO: (DEVTeam_Recipients + default_Recipients).join(", ")],
	 "Package":[name:'Package', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
	 "Publish": [name:'Publish', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
	 "Finalize":[name:'Finalize', emailTO: (ENGOPSTeam_Recipients + default_Recipients).join(", ")],
]

buildConfigs = [
	"pyside_local": "local", "pyside_Lnx": "CentOS 7.3", "pyside_Mac": "Mojave 10.14", "pyside_Win": "Windows 10"
]

//-----------------------------------------------------------------------------
def checkOS(){
    if (isUnix()) {
        def uname = sh script: 'uname', returnStdout: true
        if (uname.startsWith("Darwin")) {
            return "Mac"
        }
        else {
            return "Linux"
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

	// Default values
	def subject = "[${pysideVersion}] - ${buildStatus}: Job - '${gitBranch} [${env.BUILD_NUMBER}]'"
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
		emailTO = QTTeam_Recipients.join(", ")
	}
	else if (buildStatus == "ABORTED" || buildStatus == "UNSTABLE") {
		emailTO = default_Recipients.join(", ")
	}
	else {
		def failedStage = getFailedStage(results)
		emailTO = buildStages[failedStage].emailTO
	}

	//emailTO = "bang.nguyen@autodesk.com"

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
		//This is for affected files
		//it.Changes.each {
		//	println it
		//}
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
def GetArtifacts(String workDir, String buildConfig)
{
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
			artifactDownload.download('https://art-bobcat.autodesk.com/artifactory/', downloadspec)

			index = artifact.indexOf('/')
			print "index: ${index}"
			def downloadFile = downloadDir + artifact.substring(index)
			print "downloadFile: ${downloadFile}"
			print "${downloadFile} --- ${downloadDir}"

			if (isUnix()) {
				runOSCommand("mkdir -p ${downloadDir}")
				runOSCommand("tar zxvf ${downloadFile} -C ${downloadDir}")
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
			outputString += "https://art-bobcat.autodesk.com:443/artifactory/oss-stg-generic/pyside2/${branch}/Maya/${PysidePackage[it.key]}<br>"
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
				//println "Status: ${it.value}"
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
			if (e.toString().contains("exit code 120")) {  //Need to check return code of Warning
				currentBuild.result = 'UNSTABLE'
				if (buildConfig != "" && stage != "") {
					results[buildConfig][stage] = "Warning"
				}
			}
			else {
				print "AbortException: Error"
				currentBuild.result = 'FAILURE'
				if (buildConfig != "" && stage != "") {
					results[buildConfig][stage] = "Error"
					throw e
				}
			}
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

//-----------------------------------------------------------------------------
def getWorkspace(String buildConfig)
{
	def root = pwd()
	def index1 = root.lastIndexOf('\\')
	def index2 = root.lastIndexOf('/')
	def count = (index1 > index2 ? index1 : index2) + 1
	def workDir

	if (buildConfig.toLowerCase().contains('_local')) {
		workDir = root.take(count) + product
	}
	else {
		workDir = root.take(count) + product + '_' + branch  //Should add buildType and config too i.e. CI/DI/PF Debug/Release
	}
	println "workDir: ${workDir}"
	return workDir
}

// Execute native shell command as per OS
//-----------------------------------------------------------------------------
def runOSCommand(String cmd)
{
    try {
        if (isUnix()) {
            sh cmd
        } else {
            bat cmd
        }
    } catch(failure) {
        throw failure
    }
}

//-----------------------------------------------------------------------------
def Initialize(String buildConfig)
{
	def stage = "Initialize"

	try {
		def workDir = getWorkspace(buildConfig)
		def srcDir = "${workDir}/src"
		def scriptDir = "${workDir}/src/scripts"

		dir(srcDir) {
			scmInfo = checkout scm
			gitCommit = params.COMMIT == "" ? scmInfo.GIT_COMMIT : params.COMMIT
			println "${scm.branches} Branch: ${env.BRANCH_NAME}"

			runOSCommand("git pull")
			//Get lastBuildCommit & lastSuccessfulCommit
			buildInfo = sh (
				script: "python $scriptDir/updatebuildcommit.py -g -p ${product} -b ${branch} -t ${buildType} -c ${config}",
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
			commitInfo = sh (
				script: "python $scriptDir/getcommitinfo.py -s ${srcDir} -sc ${lastSuccessfulCommit} -bc ${lastBuildCommit} -gc ${gitCommit}",
				returnStdout: true
			).trim()
			print "CommitInfo: ${commitInfo}"
			changeSetContent = getChangeSetString(commitInfo)
		}
		workspaceRoot[buildConfig] = workDir
		hostName[buildConfig] = getHostName()
		results[buildConfig][stage] = "Success"
    } catch (e) {
		errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Setup(String buildConfig)
{
	def stage = "Setup"
	env.PYSIDEVERSION = "${pysideVersion}"
	env.QTVERSION = "${qtVersion}"
	
	try {
		def workDir = getWorkspace(buildConfig)
		ws(workDir) {
			//Delete 'build', 'install' and 'artifactory' folders before build
			dir ('build') {
				deleteDir()
			}
			dir ('install') {
				deleteDir()
			}
			dir ('out') {
				deleteDir()
			}
			dir ("${downloadDir}") {
				deleteDir()
			}
		}
		workspaceRoot[buildConfig] = workDir
		hostName[buildConfig] = getHostName()

		if (checkOS() == "Mac") {
			PysidePackage[buildConfig] = "${branch}-Maya-Pyside2-${env.BUILD_ID}-Qt-${params.QTVersion}-${params.QTBuildID}-osx10141-xcode101.tar.gz"
			artifacts[buildConfig]  = ["oss-stg-generic/Qt/${branch}/Maya/${branch}-Maya-Qt-${params.QTBuildID}-osx10141-xcode101.tar.gz"]
		}
		else if (checkOS() == "Linux") {
			PysidePackage[buildConfig] = "${branch}-Maya-Pyside2-${env.BUILD_ID}-Qt-${params.QTVersion}-${params.QTBuildID}-rhel73-gcc485.tar.gz"
			artifacts[buildConfig]  = ["oss-stg-generic/Qt/${branch}/Maya/${branch}-Maya-Qt-${params.QTBuildID}-rhel73-gcc485.tar.gz"]
		}
		else {
			PysidePackage[buildConfig] = "${branch}-Maya-Pyside2-${env.BUILD_ID}-Qt-${params.QTVersion}-${params.QTBuildID}-win-v141.zip"
			artifacts[buildConfig]  = ["oss-stg-generic/Qt/${branch}/Maya/${branch}-Maya-Qt-${params.QTBuildID}-win-v141.zip", "team-asrd-pilots/openssl/102h/openssl-1.0.2h-win-vc14.zip"]
		}

		results[buildConfig][stage] = "Success"
    } catch (e) {
		errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Sync(String workDir, String buildConfig)
{
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
				runOSCommand("git submodule update --init")
			}
			print "Commit: $gitCommit"
			//checkout scm to the commit_id
			checkout([$class: 'GitSCM', branches: [[name: gitCommit ]],
				userRemoteConfigs: scm.userRemoteConfigs])
			// Remove all private files first
			runOSCommand("git submodule foreach --recursive \"git clean -dfx\" && git clean -dfx")
            // Git pull required after first-time clone
            //runOSCommand("git submodule foreach git pull")
            runOSCommand("git submodule update --init --recursive")
		}

		print "--- Download Packages ---"
		GetArtifacts(workDir, buildConfig)

		results[buildConfig][stage] = "Success"
    } catch (e) {
		errorHandler(e, buildConfig, stage)
    }
}


//-----------------------------------------------------------------------------
def Build(String workDir, String buildConfig)
{
	def stage = "Build"
	def flavor = buildConfig.substring(0, buildConfig.lastIndexOf("_")) //We may need this to invoke different build flavors i.e. Maya/MayaLT/MayaIO
	def buildDir = "${workDir}/build"
	def srcDir = "${workDir}/src"
	def scriptDir = "${workDir}/src/scripts"

	if (isUnix()){
		runOSCommand "echo ${buildConfig} Pyside: $PYSIDEVERSION Qt: $QTVERSION"
	}
	else {
		runOSCommand "echo ${buildConfig} Pyside: %PYSIDEVERSION% Qt: %QTVERSION%"
	}
	
	try {
		//timeout(time: 9, unit: 'HOURS') {
			dir (srcDir) {
				if (checkOS() == "Mac") {
					runOSCommand('xcodebuild -version && xcodebuild -showsdks')
					runOSCommand("""export QTVERSION=${qtVersion} && bash $scriptDir/adsk_maya_build_pyside2_osx.sh ${workDir}""")
				}
				else if (checkOS() == "Linux") {
					runOSCommand("scl enable devtoolset-6 python27 'export QTVERSION=${qtVersion} && bash $scriptDir/adsk_maya_build_pyside2_lnx.sh ${workDir}'")
				}
				else {
					runOSCommand("""$scriptDir\\adsk_maya_build_pyside2_win.bat ${workDir}""")
				}
			}
		//}
		results[buildConfig][stage] = "Success"
    } catch (e) {
		errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Package(String workDir, String buildConfig)
{
  	def stage = "Package"

	try {
		def srcDir = "${workDir}/src"
		def scriptDir = "${workDir}/src/scripts"
		dir (srcDir) {
			if (checkOS() == "Mac") {
				runOSCommand("""export PYSIDEVERSION=${pysideVersion} && export QTVERSION=${qtVersion} && bash $scriptDir/adsk_maya_package_pyside2_osx.sh ${workDir}""")
			}
			else if (checkOS() == "Linux") {
				runOSCommand("""export PYSIDEVERSION=${pysideVersion} && export QTVERSION=${qtVersion} && bash $scriptDir/adsk_maya_package_pyside2_lnx.sh ${workDir}""")
			}
			else {
				runOSCommand("""$scriptDir\\adsk_maya_package_pyside2_win.bat ${workDir}""")
			}
		}

		dir(workDir) {
			dir('install') {
				if (isUnix()){
					runOSCommand("""mkdir ../out""")  //Create 'out' folder where zip files will be created.
					runOSCommand("""tar -czf ../out/${PysidePackage[buildConfig]} ${pysideVersion}""")
				} else {
					runOSCommand("""7z a -tzip ../out/${PysidePackage[buildConfig]} ${pysideVersion}""")
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

def Publish(String workDir, String buildConfig)
{
  	def stage = "Publish"
	try {
		dir(workDir) {
			artifactUpload = new ors.utils.common_artifactory(steps, env, Artifactory, 'svc-p-mayaoss')

			if (isUnix()) {
				def uploadSpec = """{
					"files": [
						{
							"pattern": "out/*.tar.gz",
							"target": "oss-stg-generic/pyside2/${branch}/Maya/",
							"recursive": "false",
							"props": "commit=${gitCommit};QtVersion=${params.QTVersion};QtBuildID=${params.QTBuildID};libclang=release_70;python=2.7"
						}
					]
				}"""

				artifactUpload.upload('https://art-bobcat.autodesk.com/artifactory/', uploadSpec)
			} else {
				def uploadSpec = """{
					"files": [
						{
							"pattern": "out/*.zip",
							"target": "oss-stg-generic/pyside2/${branch}/Maya/",
							"recursive": "false",
							"props": "commit=${gitCommit};QtVersion=${params.QTVersion};QtBuildID=${params.QTBuildID};libclang=release_70;python=2.7;OpenSSH=1.0.2h"
						}
					]
				}"""

				artifactUpload.upload('https://art-bobcat.autodesk.com/artifactory/', uploadSpec)
			}
		}
		results[buildConfig][stage] = "Success"
    } catch (e) {
		errorHandler(e, buildConfig, stage)
    }
}

//-----------------------------------------------------------------------------
def Finalize(String buildConfig)
{
	def stage = "Finalize"

	try {
		def workDir = getWorkspace(buildConfig)
		def srcDir = "${workDir}/src"
		def scriptDir = "${workDir}/src/scripts"

		dir(srcDir) {
			if (currentBuild.result == "FAILURE") {
				runOSCommand("python $scriptDir/updatebuildcommit.py -s -p ${product} -b ${branch} -t ${buildType} -c ${config} -sc ${lastSuccessfulCommit} -bc ${gitCommit}")
			} else {
				runOSCommand("python $scriptDir/updatebuildcommit.py -s -p ${product} -b ${branch} -t ${buildType} -c ${config} -sc ${gitCommit} -bc ${gitCommit}")
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

def generateSteps = {pyside_lnx, pyside_mac, pyside_win ->
    return [ "pyside_Lnx" : { node("OSS-CentOS73") { pyside_lnx() }},
             "pyside_Mac": { node("OSS-Maya-OSX10.14.1-Xcode10.1") { pyside_mac() }},
             "pyside_Win" : { node("OSS-Maya_2020_Win10-vs2107") { pyside_win() }}
           ]
}

//Initialize result matrix based on buildConfigs & stages
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
    //timeout(time: 10, unit: 'HOURS') {
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
					Setup('pyside_Lnx')
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
					Sync(workspaceRoot['pyside_Lnx'], 'pyside_Lnx')
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
					Build(workspaceRoot['pyside_Lnx'], 'pyside_Lnx')
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
					Package(workspaceRoot['pyside_Lnx'], 'pyside_Lnx')
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
					Publish(workspaceRoot['pyside_Lnx'], 'pyside_Lnx')
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
	//}
} catch (e) {
	errorHandler(e)
} finally {

	//def buildResult = getBuildResult(results, buildConfigs)
	//println "Build Result:\n${buildResult}"
	//results.each {k, v -> println "KeyResult: ${k}, KeyValue: ${v}" }
	notifyBuild(currentBuild.result, gitBranch)
}