import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const id = name => crypto.createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const objects = {};
const ref = name => ({ ref: id(name) });
const put = (name, value) => { objects[id(name)] = value; return ref(name); };
const files = directory => fs.readdirSync(path.join(root, directory)).filter(f => f.endsWith('.swift')).sort().map(f => `${directory}/${f}`);
const sourceFiles = files('App'), widgetFiles = files('Widget'), testFiles = files('Tests');
const fileRef = (file, type = 'sourcecode.swift') => put(`file:${file}`, { isa: 'PBXFileReference', lastKnownFileType: type, path: file, sourceTree: '<group>' });
const buildFile = (file, prefix) => put(`build:${prefix}:${file}`, { isa: 'PBXBuildFile', fileRef: ref(`file:${file}`) });
const appProduct = put('product:app', { isa: 'PBXFileReference', explicitFileType: 'wrapper.application', includeInIndex: 0, path: 'Sonority.app', sourceTree: 'BUILT_PRODUCTS_DIR' });
const widgetProduct = put('product:widget', { isa: 'PBXFileReference', explicitFileType: 'wrapper.app-extension', includeInIndex: 0, path: 'SonorityWidget.appex', sourceTree: 'BUILT_PRODUCTS_DIR' });
const testProduct = put('product:tests', { isa: 'PBXFileReference', explicitFileType: 'wrapper.cfbundle', includeInIndex: 0, path: 'SonorityTests.xctest', sourceTree: 'BUILT_PRODUCTS_DIR' });
const sourceRefs = [...sourceFiles, ...widgetFiles, ...testFiles].map(f => fileRef(f));
const configs = ['Config/Info.plist', 'Config/WidgetInfo.plist', 'Config/Spotify.entitlements'].map(f => fileRef(f, f.endsWith('.entitlements') ? 'text.plist.entitlements' : 'text.plist.xml'));
const assets = fileRef('App/Assets.xcassets', 'folder.assetcatalog');
put('group:products', { isa: 'PBXGroup', children: [appProduct, widgetProduct, testProduct], name: 'Products', sourceTree: '<group>' });
put('group:main', { isa: 'PBXGroup', children: [...sourceRefs, assets, ...configs, ref('group:products')], sourceTree: '<group>' });
put('package:core', { isa: 'XCLocalSwiftPackageReference', relativePath: '.' });
for (const target of ['app', 'tests']) {
    put(`core:${target}`, { isa: 'XCSwiftPackageProductDependency', package: ref('package:core'), productName: 'SonorityCore' });
    put(`corelink:${target}`, { isa: 'PBXBuildFile', productRef: ref(`core:${target}`) });
}
const sourcePhase = (target, list) => put(`sources:${target}`, { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: list.map(f => buildFile(f, target)), runOnlyForDeploymentPostprocessing: 0 });
for (const [target, list] of [['app', sourceFiles], ['widget', widgetFiles], ['tests', testFiles]]) {
    sourcePhase(target, list);
    put(`frameworks:${target}`, { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: target === 'widget' ? [] : [ref(`corelink:${target}`)], runOnlyForDeploymentPostprocessing: 0 });
    put(`resources:${target}`, { isa: 'PBXResourcesBuildPhase', buildActionMask: 2147483647, files: target === 'app' ? [buildFile('App/Assets.xcassets', 'resource')] : [], runOnlyForDeploymentPostprocessing: 0 });
}
put('embed:widget', { isa: 'PBXBuildFile', fileRef: widgetProduct, settings: { ATTRIBUTES: ['RemoveHeadersOnCopy'] } });
put('phase:embed', { isa: 'PBXCopyFilesBuildPhase', buildActionMask: 2147483647, dstPath: '', dstSubfolderSpec: 13, files: [ref('embed:widget')], name: 'Embed App Extensions', runOnlyForDeploymentPostprocessing: 0 });
put('proxy:widget', { isa: 'PBXContainerItemProxy', containerPortal: ref('project'), proxyType: 1, remoteGlobalIDString: ref('target:widget'), remoteInfo: 'SonorityWidget' });
put('dependency:widget', { isa: 'PBXTargetDependency', target: ref('target:widget'), targetProxy: ref('proxy:widget') });

function configurationList(name, settings) {
    const configurations = ['Debug', 'Release'].map(config => put(`config:${name}:${config}`, {
        isa: 'XCBuildConfiguration', name: config,
        buildSettings: { ...settings, ...(name === 'project' ? { SWIFT_OPTIMIZATION_LEVEL: config === 'Debug' ? '-Onone' : '-O', DEBUG_INFORMATION_FORMAT: config === 'Debug' ? 'dwarf' : 'dwarf-with-dsym', SWIFT_ACTIVE_COMPILATION_CONDITIONS: config === 'Debug' ? 'DEBUG $(inherited)' : '$(inherited)' } : {}) }
    }));
    return put(`configlist:${name}`, { isa: 'XCConfigurationList', buildConfigurations: configurations, defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
}
configurationList('project', { IPHONEOS_DEPLOYMENT_TARGET: '18.0', SDKROOT: 'iphoneos', SWIFT_VERSION: '5.0', CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES', ENABLE_TESTABILITY: 'YES', SWIFT_STRICT_CONCURRENCY: 'targeted' });
for (const [target, name, product, type] of [
    ['app', 'Sonority', appProduct, 'com.apple.product-type.application'],
    ['widget', 'SonorityWidget', widgetProduct, 'com.apple.product-type.app-extension'],
    ['tests', 'SonorityTests', testProduct, 'com.apple.product-type.bundle.unit-test']
]) {
    const settings = { PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: `app.sonority.${target === 'app' ? 'player' : target}`, TARGETED_DEVICE_FAMILY: '2', CODE_SIGN_STYLE: 'Automatic', DEVELOPMENT_TEAM: '', CURRENT_PROJECT_VERSION: '1', MARKETING_VERSION: '1.0', SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator', SUPPORTS_MACCATALYST: 'NO', GENERATE_INFOPLIST_FILE: target === 'tests' ? 'YES' : 'NO' };
    if (target === 'app') Object.assign(settings, { INFOPLIST_FILE: 'Config/Info.plist', ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', SPOTIFY_CLIENT_ID: '', SPOTIFY_CALLBACK_HOST: 'example.invalid', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks' });
    if (target === 'widget') Object.assign(settings, { PRODUCT_BUNDLE_IDENTIFIER: 'app.sonority.player.widget', INFOPLIST_FILE: 'Config/WidgetInfo.plist', SKIP_INSTALL: 'YES', APPLICATION_EXTENSION_API_ONLY: 'YES', LD_RUNPATH_SEARCH_PATHS: '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks' });
    const phases = [ref(`sources:${target}`), ref(`frameworks:${target}`), ref(`resources:${target}`)];
    if (target === 'app') phases.push(ref('phase:embed'));
    put(`target:${target}`, { isa: 'PBXNativeTarget', buildConfigurationList: configurationList(target, settings), buildPhases: phases, buildRules: [], dependencies: target === 'app' ? [ref('dependency:widget')] : [], name, packageProductDependencies: target === 'widget' ? [] : [ref(`core:${target}`)], productName: name, productReference: product, productType: type });
}
put('project', { isa: 'PBXProject', attributes: { BuildIndependentTargetsInParallel: 'YES', LastUpgradeCheck: '1600', TargetAttributes: { [id('target:app')]: { CreatedOnToolsVersion: '16.0' }, [id('target:widget')]: { CreatedOnToolsVersion: '16.0' }, [id('target:tests')]: { CreatedOnToolsVersion: '16.0' } } }, buildConfigurationList: ref('configlist:project'), compatibilityVersion: 'Xcode 15.0', developmentRegion: 'en', hasScannedForEncodings: 0, knownRegions: ['en', 'Base'], mainGroup: ref('group:main'), packageReferences: [ref('package:core')], productRefGroup: ref('group:products'), projectDirPath: '', projectRoot: '', targets: [ref('target:app'), ref('target:widget'), ref('target:tests')] });
function encode(value, depth = 0) {
    if (value && typeof value === 'object' && 'ref' in value) return value.ref;
    if (Array.isArray(value)) return `(\n${value.map(v => '\t'.repeat(depth + 1) + encode(v, depth + 1) + ',').join('\n')}\n${'\t'.repeat(depth)})`;
    if (value && typeof value === 'object') return `{\n${Object.entries(value).map(([key, v]) => '\t'.repeat(depth + 1) + JSON.stringify(key) + ' = ' + encode(v, depth + 1) + ';').join('\n')}\n${'\t'.repeat(depth)}}`;
    return typeof value === 'number' ? String(value) : JSON.stringify(value);
}
const project = { archiveVersion: 1, classes: {}, objectVersion: 60, objects, rootObject: ref('project') };
const projectDir = path.join(root, 'Sonority.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata/xcschemes'), { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), '// !$*UTF8*$!\n' + encode(project) + '\n');
const buildable = (target, name, extension) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:' + target)}" BuildableName="${name}.${extension}" BlueprintName="${name}" ReferencedContainer="container:Sonority.xcodeproj"/>`;
fs.writeFileSync(path.join(projectDir, 'xcshareddata/xcschemes/Sonority.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${buildable('app', 'Sonority', 'app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${buildable('tests', 'SonorityTests', 'xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('app', 'Sonority', 'app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('app', 'Sonority', 'app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`);
// Kept separately for the cross-platform validator; not used by Xcode.
fs.writeFileSync(path.join(root, 'Scripts/project-manifest.json'), JSON.stringify({ sourceFiles, widgetFiles, testFiles, objects, rootObject: id('project') }, null, 2) + '\n');
console.log(`Generated Sonority.xcodeproj: ${sourceFiles.length} app sources, widget, unit-test target, local core package.`);
