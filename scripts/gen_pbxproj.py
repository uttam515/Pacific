import os
import hashlib

def gen_id(name):
    return hashlib.md5(name.encode('utf-8')).hexdigest()[:24].upper()

source_files = [
    "App/OFFGRIDApp.swift",
    "App/ContentView.swift",
    "Features/Home/HomeDashboardView.swift",
    "Features/Home/HomeViewModel.swift",
    "Features/Chat/ChatView.swift",
    "Features/Chat/ChatViewModel.swift",
    "Features/SOS/SOSView.swift",
    "Features/SOS/SOSViewModel.swift",
    "Features/Files/FilesView.swift",
    "Features/Network/NetworkStatusView.swift",
    "Features/Network/NetworkViewModel.swift",
    "Features/Sync/SyncHistoryView.swift",
    "Features/Sync/SyncViewModel.swift",
    "Data/Database/SQLiteDatabase.swift",
    "Data/Models/NodeIdentity.swift",
    "Data/Models/OFFGRIDMessage.swift",
    "Data/Models/OFFGRIDOperation.swift",
    "Data/Repositories/MessageRepository.swift",
    "Data/Repositories/OperationQueueRepository.swift",
    "Networking/Discovery/PeerDiscoveryProtocol.swift",
    "Networking/Multipeer/MultipeerSessionManager.swift",
    "Networking/Bluetooth/BLEManager.swift",
    "Networking/Transport/TransportManager.swift",
    "Networking/Relay/RelayManager.swift",
    "Sync/SyncEngine.swift",
    "Protocol/PacketModels.swift",
    "Security/KeychainHelper.swift",
]

resource_files = [
    "Resources/Assets.xcassets",
]

# IDs
proj_id = gen_id("PROJECT_OFFGRID")
main_group_id = gen_id("GROUP_MAIN")
offgrid_group_id = gen_id("GROUP_OFFGRID")
products_group_id = gen_id("GROUP_PRODUCTS")

target_id = gen_id("TARGET_OFFGRID")
product_ref_id = gen_id("PRODUCT_OFFGRID_APP")

sources_phase_id = gen_id("PHASE_SOURCES")
frameworks_phase_id = gen_id("PHASE_FRAMEWORKS")
resources_phase_id = gen_id("PHASE_RESOURCES")

proj_cfg_debug_id = gen_id("CFG_PROJ_DEBUG")
proj_cfg_release_id = gen_id("CFG_PROJ_RELEASE")
proj_cfg_list_id = gen_id("CFG_LIST_PROJ")

target_cfg_debug_id = gen_id("CFG_TARGET_DEBUG")
target_cfg_release_id = gen_id("CFG_TARGET_RELEASE")
target_cfg_list_id = gen_id("CFG_LIST_TARGET")

info_plist_id = gen_id("FILE_INFO_PLIST")

pbx = []
pbx.append("// !$*UTF8*$!")
pbx.append("{")
pbx.append("\tarchiveVersion = 1;")
pbx.append("\tclasses = {};")
pbx.append("\tobjectVersion = 56;")
pbx.append("\tobjects = {")

# PBXBuildFile
pbx.append("\n/* Begin PBXBuildFile section */")
for f in source_files:
    bf_id = gen_id("BUILD_" + f)
    fr_id = gen_id("FILE_" + f)
    name = os.path.basename(f)
    pbx.append(f"\t\t{bf_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr_id} /* {name} */; }};")

for r in resource_files:
    bf_id = gen_id("BUILD_" + r)
    fr_id = gen_id("FILE_" + r)
    name = os.path.basename(r)
    pbx.append(f"\t\t{bf_id} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fr_id} /* {name} */; }};")
pbx.append("/* End PBXBuildFile section */")

# PBXFileReference
pbx.append("\n/* Begin PBXFileReference section */")
pbx.append(f"\t\t{product_ref_id} /* OFFGRID.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OFFGRID.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in source_files:
    fr_id = gen_id("FILE_" + f)
    name = os.path.basename(f)
    # path is relative to the OFFGRID folder
    pbx.append(f"\t\t{fr_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{f}\"; sourceTree = \"<group>\"; }};")

for r in resource_files:
    fr_id = gen_id("FILE_" + r)
    name = os.path.basename(r)
    pbx.append(f"\t\t{fr_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"{r}\"; sourceTree = \"<group>\"; }};")

pbx.append(f"\t\t{info_plist_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = \"Resources/Info.plist\"; sourceTree = \"<group>\"; }};")
pbx.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
pbx.append("\n/* Begin PBXFrameworksBuildPhase section */")
pbx.append(f"\t\t{frameworks_phase_id} /* Frameworks */ = {{")
pbx.append("\t\t\tisa = PBXFrameworksBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
pbx.append("\n/* Begin PBXGroup section */")
pbx.append(f"\t\t{main_group_id} = {{")
pbx.append("\t\t\tisa = PBXGroup;")
pbx.append("\t\t\tchildren = (")
pbx.append(f"\t\t\t\t{offgrid_group_id} /* OFFGRID */,")
pbx.append(f"\t\t\t\t{products_group_id} /* Products */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tsourceTree = \"<group>\";")
pbx.append("\t\t};")

pbx.append(f"\t\t{products_group_id} /* Products */ = {{")
pbx.append("\t\t\tisa = PBXGroup;")
pbx.append("\t\t\tchildren = (")
pbx.append(f"\t\t\t\t{product_ref_id} /* OFFGRID.app */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = Products;")
pbx.append("\t\t\tsourceTree = \"<group>\";")
pbx.append("\t\t};")

pbx.append(f"\t\t{offgrid_group_id} /* OFFGRID */ = {{")
pbx.append("\t\t\tisa = PBXGroup;")
pbx.append("\t\t\tchildren = (")
for f in source_files:
    fr_id = gen_id("FILE_" + f)
    name = os.path.basename(f)
    pbx.append(f"\t\t\t\t{fr_id} /* {name} */,")
for r in resource_files:
    fr_id = gen_id("FILE_" + r)
    name = os.path.basename(r)
    pbx.append(f"\t\t\t\t{fr_id} /* {name} */,")
pbx.append(f"\t\t\t\t{info_plist_id} /* Info.plist */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tpath = OFFGRID;")
pbx.append("\t\t\tsourceTree = \"<group>\";")
pbx.append("\t\t};")

pbx.append("/* End PBXGroup section */")

# PBXNativeTarget
pbx.append("\n/* Begin PBXNativeTarget section */")
pbx.append(f"\t\t{target_id} /* OFFGRID */ = {{")
pbx.append("\t\t\tisa = PBXNativeTarget;")
pbx.append(f"\t\t\tbuildConfigurationList = {target_cfg_list_id} /* Build configuration list for PBXNativeTarget \"OFFGRID\" */;")
pbx.append("\t\t\tbuildPhases = (")
pbx.append(f"\t\t\t\t{sources_phase_id} /* Sources */,")
pbx.append(f"\t\t\t\t{frameworks_phase_id} /* Frameworks */,")
pbx.append(f"\t\t\t\t{resources_phase_id} /* Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tbuildRules = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdependencies = (")
pbx.append("\t\t\t);")
pbx.append("\t\t\tname = OFFGRID;")
pbx.append("\t\t\tproductName = OFFGRID;")
pbx.append(f"\t\t\tproductReference = {product_ref_id} /* OFFGRID.app */;")
pbx.append("\t\t\tproductType = \"com.apple.product-type.application\";")
pbx.append("\t\t};")
pbx.append("/* End PBXNativeTarget section */")

# PBXProject
pbx.append("\n/* Begin PBXProject section */")
pbx.append(f"\t\t{proj_id} /* Project object */ = {{")
pbx.append("\t\t\tisa = PBXProject;")
pbx.append("\t\t\tattributes = {")
pbx.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
pbx.append("\t\t\t\tLastUpgradeCheck = 1600;")
pbx.append("\t\t\t};")
pbx.append(f"\t\t\tbuildConfigurationList = {proj_cfg_list_id} /* Build configuration list for PBXProject \"OFFGRID\" */;")
pbx.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
pbx.append("\t\t\tdevelopmentRegion = en;")
pbx.append("\t\t\thasScannedForEncodings = 0;")
pbx.append("\t\t\tknownRegions = (")
pbx.append("\t\t\t\ten,")
pbx.append("\t\t\t\tBase,")
pbx.append("\t\t\t);")
pbx.append(f"\t\t\tmainGroup = {main_group_id};")
pbx.append(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
pbx.append("\t\t\tprojectDirPath = \"\";")
pbx.append("\t\t\tprojectRoot = \"\";")
pbx.append("\t\t\ttargets = (")
pbx.append(f"\t\t\t\t{target_id} /* OFFGRID */,")
pbx.append("\t\t\t);")
pbx.append("\t\t};")
pbx.append("/* End PBXProject section */")

# PBXResourcesBuildPhase
pbx.append("\n/* Begin PBXResourcesBuildPhase section */")
pbx.append(f"\t\t{resources_phase_id} /* Resources */ = {{")
pbx.append("\t\t\tisa = PBXResourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for r in resource_files:
    bf_id = gen_id("BUILD_" + r)
    name = os.path.basename(r)
    pbx.append(f"\t\t\t\t{bf_id} /* {name} in Resources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
pbx.append("\n/* Begin PBXSourcesBuildPhase section */")
pbx.append(f"\t\t{sources_phase_id} /* Sources */ = {{")
pbx.append("\t\t\tisa = PBXSourcesBuildPhase;")
pbx.append("\t\t\tbuildActionMask = 2147483647;")
pbx.append("\t\t\tfiles = (")
for f in source_files:
    bf_id = gen_id("BUILD_" + f)
    name = os.path.basename(f)
    pbx.append(f"\t\t\t\t{bf_id} /* {name} in Sources */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
pbx.append("\t\t};")
pbx.append("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
pbx.append("\n/* Begin XCBuildConfiguration section */")
pbx.append(f"\t\t{proj_cfg_debug_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
pbx.append("\t\t\t\tENABLE_TESTABILITY = YES;")
pbx.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
pbx.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
pbx.append("\t\t\t\tMTL_FAST_MATH = YES;")
pbx.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
pbx.append("\t\t\t\tSDKROOT = iphoneos;")
pbx.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";")
pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

pbx.append(f"\t\t{proj_cfg_release_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
pbx.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tMTL_FAST_MATH = YES;")
pbx.append("\t\t\t\tSDKROOT = iphoneos;")
pbx.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
pbx.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")

pbx.append(f"\t\t{target_cfg_debug_id} /* Debug */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = OFFGRID/Resources/Info.plist;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\";")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.offgrid.mesh;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Debug;")
pbx.append("\t\t};")

pbx.append(f"\t\t{target_cfg_release_id} /* Release */ = {{")
pbx.append("\t\t\tisa = XCBuildConfiguration;")
pbx.append("\t\t\tbuildSettings = {")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
pbx.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
pbx.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
pbx.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
pbx.append("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
pbx.append("\t\t\t\tINFOPLIST_FILE = OFFGRID/Resources/Info.plist;")
pbx.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
pbx.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\";")
pbx.append("\t\t\t\tMARKETING_VERSION = 1.0;")
pbx.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = org.offgrid.mesh;")
pbx.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
pbx.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
pbx.append("\t\t\t\tSWIFT_VERSION = 5.0;")
pbx.append("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
pbx.append("\t\t\t};")
pbx.append("\t\t\tname = Release;")
pbx.append("\t\t};")
pbx.append("/* End XCBuildConfiguration section */")

# XCConfigurationList
pbx.append("\n/* Begin XCConfigurationList section */")
pbx.append(f"\t\t{proj_cfg_list_id} /* Build configuration list for PBXProject \"OFFGRID\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{proj_cfg_debug_id} /* Debug */,")
pbx.append(f"\t\t\t\t{proj_cfg_release_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")

pbx.append(f"\t\t{target_cfg_list_id} /* Build configuration list for PBXNativeTarget \"OFFGRID\" */ = {{")
pbx.append("\t\t\tisa = XCConfigurationList;")
pbx.append("\t\t\tbuildConfigurations = (")
pbx.append(f"\t\t\t\t{target_cfg_debug_id} /* Debug */,")
pbx.append(f"\t\t\t\t{target_cfg_release_id} /* Release */,")
pbx.append("\t\t\t);")
pbx.append("\t\t\tdefaultConfigurationIsVisible = 0;")
pbx.append("\t\t\tdefaultConfigurationName = Release;")
pbx.append("\t\t};")
pbx.append("/* End XCConfigurationList section */")

pbx.append("\t};")
pbx.append(f"\trootObject = {proj_id} /* Project object */;")
pbx.append("}")

output_dir = "/Users/uttam/Pacific/apps/ios/OFFGRID.xcodeproj"
os.makedirs(output_dir, exist_ok=True)
with open(os.path.join(output_dir, "project.pbxproj"), "w") as f:
    f.write("\n".join(pbx) + "\n")

print("Created project.pbxproj with accurate relative paths!")
