#!/usr/bin/env python3
"""Keep optional release lookup failure separate from iOS matchmaking readiness."""
from pathlib import Path
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET

REVIEWED_SIGNED_UPDATER_SHA256 = '36bbe71b2eef1d82fe5791d3ee278d2cfcecf4bcb972cb3c51c329b8da204c94'
NETWORK_FAILURE = '''            if (request.result != UnityWebRequest.Result.Success)
            {
                Logger.Error($"GitHub request failed: {request.responseCode} {request.error}", "CheckRelease");
                IsBroken = true;
                yield break;
            }'''
PARSE_FAILURE = '''        catch (Exception ex)
        {
            IsBroken = true;

            Logger.Error(
                $"Error while checking release from GitHub:\\n{ex}",
                "CheckRelease",
                false
            );
        }'''
GUARDED_FAILURE = 'if (!OperatingSystem.IsIOS()) IsBroken = true;'
START = '    private static IEnumerator CheckReleaseFromGithub(bool beta = false)'
END = '\n#if IL2CPP\n    private static string FindDllAssetUrl'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def adapt_source(data, expected_sha256):
    if sha(data) != expected_sha256:
        raise ValueError('Selected signed updater hash differs')
    bom = data.startswith(b'\xef\xbb\xbf')
    eol = '\r\n' if b'\r\n' in data else '\n'
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    if (text.count(START) != 1 or text.count(END) != 1 or
            text.count('IsBroken = true;') != 2 or GUARDED_FAILURE in text):
        raise ValueError('Reviewed remote-only updater state changed')
    start, end = text.index(START), text.index(END)
    if end <= start:
        raise ValueError('Updater method boundary changed')
    body = text[start:end]
    for span in (NETWORK_FAILURE, PARSE_FAILURE):
        if text.count(span) != 1 or body.count(span) != 1:
            raise ValueError('Reviewed optional lookup failure branch changed')
    if 'DownloadUrl = global::EHR.SourceHost.SourceSignedUpdates.ConfiguredUrl;' not in body:
        raise ValueError('Signed iOS updater must be selected before this overlay')
    result = text
    for span in (NETWORK_FAILURE, PARSE_FAILURE):
        result = result.replace(span, span.replace('IsBroken = true;', GUARDED_FAILURE), 1)
    if result.replace(GUARDED_FAILURE, 'IsBroken = true;') != text:
        raise ValueError('Bytes outside the two failure assignments changed')
    output = result.replace('\n', eol).encode('utf-8')
    if bom:
        output = b'\xef\xbb\xbf' + output
    if output.replace(GUARDED_FAILURE.encode(), b'IsBroken = true;') != data:
        raise ValueError('Input byte format or unrelated source changed')
    return output


def prepare(project, output, expected_sha256):
    project, output = project.resolve(), output.resolve()
    if output.exists() or any((root / '.git').exists() for root in (output, *output.parents)):
        raise ValueError('A fresh outside-Git output is required')
    tree = ET.parse(project)
    matches = []
    for node in tree.getroot().iter():
        include = node.get('Include')
        if node.tag.split('}')[-1] == 'Compile' and include and Path(include).name == 'ModUpdater.cs':
            source = Path(include)
            source = source if source.is_absolute() else project.parent / source
            matches.append((node, source.resolve()))
    if len(matches) != 1:
        raise ValueError('Exactly one selected ModUpdater.cs is required')
    item, source = matches[0]
    before = source.read_bytes()
    after = adapt_source(before, expected_sha256)
    (output / 'source').mkdir(parents=True)
    target = output / 'source/ModUpdater.cs'
    target.write_bytes(after)
    item.set('Include', str(target))
    for node in tree.getroot().iter():
        if node.tag.split('}')[-1] not in ('Compile', 'EmbeddedResource', 'Import'):
            continue
        for key in ('Include', 'Project'):
            value = node.get(key)
            if value and not Path(value).is_absolute() and '$(' not in value and '*' not in value:
                node.set(key, str((project.parent / value).resolve()))
    tree.write(output / 'EHR.csproj', encoding='unicode')
    report = {
        'schema': 'ehr.ios-optional-update-lookup.v1',
        'input_project': str(project), 'input_project_sha256': sha(project.read_bytes()),
        'input': str(source), 'input_sha256': sha(before), 'output_sha256': sha(after),
        'only_two_remote_failure_assignments_changed': True,
        'ios_optional_lookup_no_longer_marks_mod_broken': True,
        'failure_logs_and_lookup_version_comparison_unchanged': True,
        'all_consumers_native_permissions_protocol_registration_unchanged': True,
        'desktop_android_behavior_unchanged': True,
        'preview24_1_finder_cause_diagnosed': False,
        'authenticated_backend_and_physical_finder_verified': False,
    }
    (output / 'update-lookup-overlay.json').write_text(json.dumps(report, indent=2) + '\n')
    return output / 'EHR.csproj'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-updater-sha256', default=REVIEWED_SIGNED_UPDATER_SHA256)
    args = parser.parse_args(argv)
    print(prepare(args.project, args.output, args.expected_updater_sha256))


if __name__ == '__main__':
    main()
