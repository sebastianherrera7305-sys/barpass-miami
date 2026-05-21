#!/usr/bin/env python3
"""Generates a valid Xcode .xcodeproj for BarPass iOS.
NOTE: The pbxproj is written as a static template with fixed GUIDs.
      Do NOT regenerate it with new random UUIDs — the scheme file
      references specific GUIDs (AA000005...) that must stay stable.
"""
import os, uuid, json

BASE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(BASE, "BarPass.xcodeproj")
os.makedirs(os.path.join(PROJ, "project.xcworkspace"), exist_ok=True)

def uid():
    return uuid.uuid4().hex[:24].upper()

# ── IDs ───────────────────────────────────────────────────────────────────────
IDS = {k: uid() for k in [
    "PROJECT","TARGET","BUILD_CFG_APP_DBG","BUILD_CFG_APP_REL",
    "BUILD_CFG_PROJ_DBG","BUILD_CFG_PROJ_REL","CFG_LIST_APP","CFG_LIST_PROJ",
    "MAIN_GROUP","SRC_GROUP","CORE_GROUP","WEBVIEW_GRP","BRIDGE_GRP",
    "SERVICES_GRP","CACHE_GRP","FEATURES_GRP","SPLASH_GRP","WALLETPASS_GRP",
    "RESOURCES_GRP","WEB_GRP","PRODUCTS_GRP","COMPILE_PHASE","RESOURCES_PHASE",
    "LINK_PHASE","PRODUCT_REF","HTML_REF","HTML_BUILD","PLIST_REF","ASSETS_REF",
    "ASSETS_BUILD","ENTITLEMENTS_REF",
]}
I = IDS

SWIFT_FILES = [
    ("App",         "BarPassApp.swift",          "BarPass/BarPassApp.swift"),
    ("App",         "AppState.swift",             "BarPass/AppState.swift"),
    ("Features",    "RootView.swift",             "BarPass/Features/RootView.swift"),
    ("Splash",      "SplashView.swift",           "BarPass/Features/Splash/SplashView.swift"),
    ("WalletPass",  "WalletPassService.swift",    "BarPass/Core/Services/WalletPassService.swift"),
    ("WalletPass",  "AppleWalletButton.swift",    "BarPass/Features/WalletPass/AppleWalletButton.swift"),
    ("WebView",     "BarPassWebView.swift",       "BarPass/Core/WebView/BarPassWebView.swift"),
    ("WebView",     "WebViewCoordinator.swift",   "BarPass/Core/WebView/WebViewCoordinator.swift"),
    ("Bridge",      "NativeBridge.swift",         "BarPass/Core/Bridge/NativeBridge.swift"),
    ("Services",    "HapticService.swift",        "BarPass/Core/Services/HapticService.swift"),
    ("Services",    "LocationService.swift",      "BarPass/Core/Services/LocationService.swift"),
    ("Services",    "NotificationService.swift",  "BarPass/Core/Services/NotificationService.swift"),
    ("Services",    "BiometricService.swift",     "BarPass/Core/Services/BiometricService.swift"),
    ("Services",    "ApplePayService.swift",      "BarPass/Core/Services/ApplePayService.swift"),
    ("Cache",       "CacheManager.swift",         "BarPass/Core/Cache/CacheManager.swift"),
]

files = [{"grp": g, "name": n, "path": p, "ref": uid(), "build": uid()} for g,n,p in SWIFT_FILES]

# ── Builder ───────────────────────────────────────────────────────────────────
out = []

def ln(s=""): out.append(s)
def section(name, start=True):
    if start: ln(f"\n/* Begin {name} section */")
    else:     ln(f"/* End {name} section */")

def obj_start(oid, comment=""):
    c = f" /* {comment} */" if comment else ""
    ln(f"\t\t{oid}{c} = {{")

def obj_end(): ln("\t\t};")
def attr(k, v, indent=3): ln(f"{'	'*indent}{k} = {v};")
def children_start(): ln("\t\t\tchildren = (")
def children_end(): ln("\t\t\t);")
def child(oid, comment=""): ln(f"\t\t\t\t{oid}{' /* '+comment+' */' if comment else ''},")
def files_list(items, label):
    ln(f"\t\t\t{label} = (")
    for item in items: ln(f"\t\t\t\t{item},")
    ln("\t\t\t);")

# ── Header ────────────────────────────────────────────────────────────────────
ln("// !$*UTF8*$!")
ln("{")
ln("\tarchiveVersion = 1;")
ln("\tclasses = {")
ln("\t};")
ln("\tobjectVersion = 77;")
ln("\tobjects = {")

# ── PBXBuildFile ──────────────────────────────────────────────────────────────
section("PBXBuildFile")
for f in files:
    ln(f"\t\t{f['build']} /* {f['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {f['ref']} /* {f['name']} */; }};")
ln(f"\t\t{I['HTML_BUILD']} /* barpass-miami.html in Resources */ = {{isa = PBXBuildFile; fileRef = {I['HTML_REF']} /* barpass-miami.html */; }};")
ln(f"\t\t{I['ASSETS_BUILD']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {I['ASSETS_REF']} /* Assets.xcassets */; }};")
section("PBXBuildFile", False)

# ── PBXFileReference ──────────────────────────────────────────────────────────
section("PBXFileReference")
for f in files:
    ln(f"\t\t{f['ref']} /* {f['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{f['name']}\"; sourceTree = \"<group>\"; }};")
ln(f"\t\t{I['HTML_REF']} /* barpass-miami.html */ = {{isa = PBXFileReference; lastKnownFileType = text.html; path = \"barpass-miami.html\"; sourceTree = \"<group>\"; }};")
ln(f"\t\t{I['PLIST_REF']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
ln(f"\t\t{I['ASSETS_REF']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
ln(f"\t\t{I['ENTITLEMENTS_REF']} /* BarPass.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BarPass.entitlements; sourceTree = \"<group>\"; }};")
ln(f"\t\t{I['PRODUCT_REF']} /* BarPass.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BarPass.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
section("PBXFileReference", False)

# ── PBXFrameworksBuildPhase ───────────────────────────────────────────────────
section("PBXFrameworksBuildPhase")
obj_start(I['LINK_PHASE'], "Frameworks")
attr("isa", "PBXFrameworksBuildPhase")
attr("buildActionMask", "2147483647")
ln("\t\t\tfiles = (")
ln("\t\t\t);")
attr("runOnlyForDeploymentPostprocessing", "0")
obj_end()
section("PBXFrameworksBuildPhase", False)

# ── PBXGroup ──────────────────────────────────────────────────────────────────
section("PBXGroup")

# Root group
obj_start(I['MAIN_GROUP'])
attr("isa", "PBXGroup")
children_start()
child(I['SRC_GROUP'], "BarPass")
child(I['PRODUCTS_GRP'], "Products")
children_end()
attr("sourceTree", "\"<group>\"")
obj_end()

# Products
obj_start(I['PRODUCTS_GRP'], "Products")
attr("isa", "PBXGroup")
children_start()
child(I['PRODUCT_REF'], "BarPass.app")
children_end()
attr("name", "Products")
attr("sourceTree", "\"<group>\"")
obj_end()

# App source root
app_files = [f for f in files if f['grp'] == 'App']
obj_start(I['SRC_GROUP'], "BarPass")
attr("isa", "PBXGroup")
children_start()
for f in app_files:
    child(f['ref'], f['name'])
child(I['CORE_GROUP'], "Core")
child(I['FEATURES_GRP'], "Features")
child(I['RESOURCES_GRP'], "Resources")
child(I['WEB_GRP'], "Web")
child(I['ENTITLEMENTS_REF'], "BarPass.entitlements")
children_end()
attr("path", "BarPass")
attr("sourceTree", "\"<group>\"")
obj_end()

# Core
obj_start(I['CORE_GROUP'], "Core")
attr("isa", "PBXGroup")
children_start()
child(I['WEBVIEW_GRP'], "WebView")
child(I['BRIDGE_GRP'], "Bridge")
child(I['SERVICES_GRP'], "Services")
child(I['CACHE_GRP'], "Cache")
children_end()
attr("name", "Core")
attr("path", "Core")
attr("sourceTree", "\"<group>\"")
obj_end()

# Subgroups of Core
for grp_id, grp_name in [(I['WEBVIEW_GRP'],"WebView"),(I['BRIDGE_GRP'],"Bridge"),(I['SERVICES_GRP'],"Services"),(I['CACHE_GRP'],"Cache")]:
    grp_files = [f for f in files if f['grp'] == grp_name]
    obj_start(grp_id, grp_name)
    attr("isa", "PBXGroup")
    children_start()
    for f in grp_files: child(f['ref'], f['name'])
    children_end()
    attr("name", grp_name)
    attr("path", grp_name)
    attr("sourceTree", "\"<group>\"")
    obj_end()

# Features
feat_files = [f for f in files if f['grp'] == 'Features']
obj_start(I['FEATURES_GRP'], "Features")
attr("isa", "PBXGroup")
children_start()
for f in feat_files: child(f['ref'], f['name'])
child(I['SPLASH_GRP'], "Splash")
child(I['WALLETPASS_GRP'], "WalletPass")
children_end()
attr("name", "Features")
attr("path", "Features")
attr("sourceTree", "\"<group>\"")
obj_end()

splash_files = [f for f in files if f['grp'] == 'Splash']
obj_start(I['SPLASH_GRP'], "Splash")
attr("isa", "PBXGroup")
children_start()
for f in splash_files: child(f['ref'], f['name'])
children_end()
attr("name", "Splash")
attr("path", "Splash")
attr("sourceTree", "\"<group>\"")
obj_end()

walletpass_files = [f for f in files if f['grp'] == 'WalletPass']
obj_start(I['WALLETPASS_GRP'], "WalletPass")
attr("isa", "PBXGroup")
children_start()
for f in walletpass_files: child(f['ref'], f['name'])
children_end()
attr("name", "WalletPass")
attr("path", "WalletPass")
attr("sourceTree", "\"<group>\"")
obj_end()

# Resources
obj_start(I['RESOURCES_GRP'], "Resources")
attr("isa", "PBXGroup")
children_start()
child(I['PLIST_REF'], "Info.plist")
child(I['ASSETS_REF'], "Assets.xcassets")
children_end()
attr("name", "Resources")
attr("path", "Resources")
attr("sourceTree", "\"<group>\"")
obj_end()

# Web
obj_start(I['WEB_GRP'], "Web")
attr("isa", "PBXGroup")
children_start()
child(I['HTML_REF'], "barpass-miami.html")
children_end()
attr("name", "Web")
attr("path", "Web")
attr("sourceTree", "\"<group>\"")
obj_end()

section("PBXGroup", False)

# ── PBXNativeTarget ───────────────────────────────────────────────────────────
section("PBXNativeTarget")
obj_start(I['TARGET'], "BarPass")
attr("isa", "PBXNativeTarget")
attr("buildConfigurationList", f"{I['CFG_LIST_APP']} /* Build configuration list for PBXNativeTarget \"BarPass\" */")
ln(f"\t\t\tbuildPhases = (")
ln(f"\t\t\t\t{I['COMPILE_PHASE']} /* Sources */,")
ln(f"\t\t\t\t{I['RESOURCES_PHASE']} /* Resources */,")
ln(f"\t\t\t\t{I['LINK_PHASE']} /* Frameworks */,")
ln(f"\t\t\t);")
ln("\t\t\tbuildRules = ();")
ln("\t\t\tdependencies = ();")
attr("name", "BarPass")
attr("packageProductDependencies", "()")
attr("productName", "BarPass")
attr("productReference", f"{I['PRODUCT_REF']} /* BarPass.app */")
attr("productType", "\"com.apple.product-type.application\"")
obj_end()
section("PBXNativeTarget", False)

# ── PBXProject ────────────────────────────────────────────────────────────────
section("PBXProject")
obj_start(I['PROJECT'], "Project object")
attr("isa", "PBXProject")
ln("\t\t\tattributes = {")
ln("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
ln("\t\t\t\tLastSwiftUpdateCheck = 1700;")
ln("\t\t\t\tLastUpgradeCheck = 1700;")
ln(f"\t\t\t\tTargetAttributes = {{")
ln(f"\t\t\t\t\t{I['TARGET']} = {{")
ln(f"\t\t\t\t\t\tCreatedOnToolsVersion = 17.0;")
ln(f"\t\t\t\t\t}};")
ln(f"\t\t\t\t}};")
ln("\t\t\t};")
attr("buildConfigurationList", f"{I['CFG_LIST_PROJ']} /* Build configuration list for PBXProject \"BarPass\" */")
attr("compatibilityVersion", "\"Xcode 14.0\"")
attr("developmentRegion", "en")
attr("hasScannedForEncodings", "0")
ln("\t\t\tknownRegions = (")
ln("\t\t\t\ten,")
ln("\t\t\t\tBase,")
ln("\t\t\t);")
attr("mainGroup", I['MAIN_GROUP'])
ln("\t\t\tpackageReferences = ();")
attr("productRefGroup", f"{I['PRODUCTS_GRP']} /* Products */")
attr("projectDirPath", "\"\"")
attr("projectRoot", "\"\"")
ln(f"\t\t\ttargets = (")
ln(f"\t\t\t\t{I['TARGET']} /* BarPass */,")
ln(f"\t\t\t);")
obj_end()
section("PBXProject", False)

# ── PBXResourcesBuildPhase ────────────────────────────────────────────────────
section("PBXResourcesBuildPhase")
obj_start(I['RESOURCES_PHASE'], "Resources")
attr("isa", "PBXResourcesBuildPhase")
attr("buildActionMask", "2147483647")
ln("\t\t\tfiles = (")
ln(f"\t\t\t\t{I['HTML_BUILD']} /* barpass-miami.html in Resources */,")
ln(f"\t\t\t\t{I['ASSETS_BUILD']} /* Assets.xcassets in Resources */,")
ln("\t\t\t);")
attr("runOnlyForDeploymentPostprocessing", "0")
obj_end()
section("PBXResourcesBuildPhase", False)

# ── PBXSourcesBuildPhase ──────────────────────────────────────────────────────
section("PBXSourcesBuildPhase")
obj_start(I['COMPILE_PHASE'], "Sources")
attr("isa", "PBXSourcesBuildPhase")
attr("buildActionMask", "2147483647")
ln("\t\t\tfiles = (")
for f in files:
    ln(f"\t\t\t\t{f['build']} /* {f['name']} in Sources */,")
ln("\t\t\t);")
attr("runOnlyForDeploymentPostprocessing", "0")
obj_end()
section("PBXSourcesBuildPhase", False)

# ── XCBuildConfiguration ──────────────────────────────────────────────────────
section("XCBuildConfiguration")

def write_build_config(cfg_id, name, release, is_target):
    obj_start(cfg_id, name)
    attr("isa", "XCBuildConfiguration")
    ln("\t\t\tbuildSettings = {")
    if is_target:
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "BarPass/Resources/Info.plist",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "MARKETING_VERSION": "1.0",
            "CODE_SIGN_ENTITLEMENTS": "BarPass/Resources/BarPass.entitlements",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.barpass.app",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "6.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if not release else '"-Owholemodule"',
        }
    else:
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_WARN_BOOL_CONVERSION": "YES",
            "CLANG_WARN_EMPTY_BODY": "YES",
            "CLANG_WARN_ENUM_CONVERSION": "YES",
            "CLANG_WARN_INT_CONVERSION": "YES",
            "CLANG_WARN_UNREACHABLE_CODE": "YES",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
            "GCC_WARN_UNDECLARED_SELECTOR": "YES",
            "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
            "GCC_WARN_UNUSED_FUNCTION": "YES",
            "GCC_WARN_UNUSED_VARIABLE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "MTL_ENABLE_DEBUG_INFO": ("NO" if release else "INCLUDE_SOURCE"),
            "SDKROOT": "iphoneos",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ('""' if release else "DEBUG"),
            "VALIDATE_PRODUCT": ("YES" if release else "NO"),
        }
        if not release:
            settings["ONLY_ACTIVE_ARCH"] = "YES"
    for k, v in settings.items():
        ln(f"\t\t\t\t{k} = {v};")
    ln("\t\t\t};")
    attr("name", name)
    obj_end()

write_build_config(I['BUILD_CFG_PROJ_DBG'], "Debug",   False, False)
write_build_config(I['BUILD_CFG_PROJ_REL'], "Release", True,  False)
write_build_config(I['BUILD_CFG_APP_DBG'],  "Debug",   False, True)
write_build_config(I['BUILD_CFG_APP_REL'],  "Release", True,  True)

section("XCBuildConfiguration", False)

# ── XCConfigurationList ───────────────────────────────────────────────────────
section("XCConfigurationList")
obj_start(I['CFG_LIST_PROJ'], "Build configuration list for PBXProject \"BarPass\"")
attr("isa", "XCConfigurationList")
ln(f"\t\t\tbuildConfigurations = ({I['BUILD_CFG_PROJ_DBG']} /* Debug */, {I['BUILD_CFG_PROJ_REL']} /* Release */,);")
attr("defaultConfigurationIsVisible", "0")
attr("defaultConfigurationName", "Release")
obj_end()

obj_start(I['CFG_LIST_APP'], "Build configuration list for PBXNativeTarget \"BarPass\"")
attr("isa", "XCConfigurationList")
ln(f"\t\t\tbuildConfigurations = ({I['BUILD_CFG_APP_DBG']} /* Debug */, {I['BUILD_CFG_APP_REL']} /* Release */,);")
attr("defaultConfigurationIsVisible", "0")
attr("defaultConfigurationName", "Release")
obj_end()
section("XCConfigurationList", False)

# ── Footer ────────────────────────────────────────────────────────────────────
ln("\t};")
ln(f"\trootObject = {I['PROJECT']} /* Project object */;")
ln("}")

# Write files
pbxproj = os.path.join(PROJ, "project.pbxproj")
with open(pbxproj, "w") as f:
    f.write("\n".join(out))

ws = os.path.join(PROJ, "project.xcworkspace", "contents.xcworkspacedata")
with open(ws, "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')

# Write scheme with correct target GUID
schemes_dir = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(schemes_dir, exist_ok=True)
with open(os.path.join(schemes_dir, "BarPass.xcscheme"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES" buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I["TARGET"]}" BuildableName = "BarPass.app" BlueprintName = "BarPass" ReferencedContainer = "container:BarPass.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I["TARGET"]}" BuildableName = "BarPass.app" BlueprintName = "BarPass" ReferencedContainer = "container:BarPass.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
''')

# Assets
assets = os.path.join(BASE, "BarPass", "Resources", "Assets.xcassets")
os.makedirs(os.path.join(assets, "AppIcon.appiconset"), exist_ok=True)
with open(os.path.join(assets, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f)
with open(os.path.join(assets, "AppIcon.appiconset", "Contents.json"), "w") as f:
    json.dump({"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, f)

print(f"✅  {pbxproj}")
print(f"👉  open {PROJ}")
