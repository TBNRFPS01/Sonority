import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'Scripts/project-manifest.json'), 'utf8'));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
let count = 0;
function check(name, fn) { fn(); count++; console.log(`PASS ${name}`); }
check('All project object references resolve', () => {
    function visit(value) {
        if (value && typeof value === 'object' && 'ref' in value) assert.ok(manifest.objects[value.ref], `Unresolved ${value.ref}`);
        else if (value && typeof value === 'object') Object.values(value).forEach(visit);
    }
    visit(manifest.objects);
});
check('All referenced sources and configuration files exist', () => {
    for (const object of Object.values(manifest.objects)) if (object.isa === 'PBXFileReference' && object.sourceTree === '<group>') assert.ok(fs.existsSync(path.join(root, object.path)), object.path);
});
check('No app or widget source is omitted from the project', () => {
    for (const [folder, list] of [['App', manifest.sourceFiles], ['Widget', manifest.widgetFiles], ['Tests', manifest.testFiles]]) assert.deepEqual(fs.readdirSync(path.join(root, folder)).filter(f => f.endsWith('.swift')).sort().map(f => `${folder}/${f}`), list);
});
check('App, widget, and test targets have source build phases', () => {
    const targets = Object.values(manifest.objects).filter(v => v.isa === 'PBXNativeTarget');
    assert.equal(targets.length, 3);
    for (const target of targets) assert.ok(target.buildPhases.some(p => { const phase = manifest.objects[p.ref]; return phase.isa === 'PBXSourcesBuildPhase' && phase.files.length > 0; }));
});
check('Swift package includes the core and behavioral tests', () => {
    assert.match(read('Package.swift'), /path: "Core"/); assert.match(read('Package.swift'), /path: "Tests"/);
    assert.ok((read('Tests/CoreTests.swift').match(/func test/g) || []).length >= 6);
});
check('Background audio, multitasking orientations, and navigation scheme are declared', () => {
    const plist = read('Config/Info.plist'); assert.match(plist, /UIBackgroundModes/); assert.match(plist, /<string>audio<\/string>/);
    assert.equal((plist.match(/<string>UIInterfaceOrientation/g) || []).length, 4); assert.match(plist, /<string>sonority<\/string>/);
    assert.doesNotMatch(plist, /UIRequiresFullScreen/);
});
check('No insecure network exceptions or shipped developer credentials', () => {
    assert.doesNotMatch(read('Config/Info.plist'), /NSAllowsArbitraryLoads/);
    assert.match(read('App/SpotifyClient.swift'), /S256/); assert.match(read('App/SpotifyClient.swift'), /SecRandomCopyBytes/);
    for (const object of Object.values(manifest.objects)) if (object.isa === 'XCBuildConfiguration' && 'SPOTIFY_CLIENT_ID' in object.buildSettings) assert.equal(object.buildSettings.SPOTIFY_CLIENT_ID, '');
});
check('Spotify requests stay separate from local decoding', () => {
    assert.doesNotMatch(read('App/AudioPlayer.swift'), /spotify\.com|SPTAppRemote/);
    assert.doesNotMatch(read('App/SpotifyClient.swift'), /AVAudioFile|AVAudioEngine/);
    assert.match(read('App/SpotifyClient.swift'), /api\.spotify\.com/);
});
check('Shared scheme includes the unit tests', () => { assert.match(read('Sonority.xcodeproj/xcshareddata/xcschemes/Sonority.xcscheme'), /SonorityTests.xctest/); });
console.log(`\n${count} project integrity checks passed. These checks do not compile Swift or exercise Apple frameworks.`);
