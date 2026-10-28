#!/usr/bin/env python3
"""Pinned protected-profile policy, unavailable directory, and read-only /level."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
POLICY=HERE/'account_protection_policy.json'
LABEL='EHR website lobby directory: unavailable (account-protected iOS)'
MESSAGE='The EHR website lobby directory is unavailable in this account-protected iOS build.'
LEVEL_MESSAGE='This iOS test profile does not change player levels.'


def sha(data):return hashlib.sha256(data).hexdigest()
def once(data,before,after):
 if data.count(before)!=1:raise ValueError('Pinned source adaptation anchor is absent or ambiguous')
 return data.replace(before,after)
def newline(data):return b'\r\n'if b'\r\n'in data else b'\n'
def with_newline(data,eol):return data.replace(b'\r\n',b'\n').replace(b'\n',eol)
def encoded(text,eol):return text.replace('\n',eol.decode()).encode()
def span(data,start,end):
 if data.count(start)!=1:raise ValueError('Pinned declaration start is absent or ambiguous')
 begin=data.index(start);finish=data.find(end,begin+len(start))
 if finish<0:raise ValueError('Pinned declaration end missing')
 return data[begin:finish]


def policy_source(policy):
 rows=policy['excluded_callbacks'];lines=['// Original descriptor policy; no game state or provider calls.\n#nullable enable\nnamespace EHR;\n\ninternal static class EHRSourceAccountPolicy\n{\n',
 '    internal const string UpstreamCommit = '+json.dumps(policy['upstream_commit'])+';\n',
 '    internal const int ExcludedCallbackCount = '+str(len(rows))+';\n',
 '    internal static bool TryExclude(string callbackId, out string reason)\n    {\n        reason = callbackId switch\n        {\n']
 for row in rows:lines.append('            '+json.dumps(row['callback_id'])+' => '+json.dumps(row['reason'])+',\n')
 lines.append('            _ => string.Empty\n        };\n        return reason.Length != 0;\n    }\n}\n')
 return ''.join(lines)


def validate_descriptors(policy,audit,selectors):
 pin=policy['upstream_commit']
 if audit.get('upstreamCommit')!=pin or selectors.get('upstreamCommit')!=pin or audit.get('compileProfile')!='IL2CPP'or selectors.get('compileProfile')!='IL2CPP':raise ValueError('Descriptor inventory source pin/profile differs')
 callbacks={r['id']:r for r in audit['rows']};targets={r['selectorId']:r for r in selectors['selectors']}
 if len(callbacks)!=len(audit['rows'])or len(targets)!=len(selectors['selectors']):raise ValueError('Duplicate descriptor/selector identity')
 excluded=set()
 for row in policy['excluded_callbacks']:
  callback=callbacks.get(row['callback_id']);target=targets.get(row['selector_id'])
  if row['callback_id']in excluded or not callback or callback['sourceFile']!=row['source_file']or not target or row['callback_id']not in target['callbackIds']:raise ValueError('Exact protected callback/selector/source identity differs')
  if callback['classId']+'::'+callback['method']+'#'+str(callback['index'])!=row['callback_id']:raise ValueError('Callback declaration identity differs')
  associated=[s['selectorId']for s in selectors['selectors']if row['callback_id']in s['callbackIds']]
  if associated!=[row['selector_id']]:raise ValueError('Protected callback target set differs')
  excluded.add(row['callback_id'])
 return [{'selector_id':r['selectorId'],'allowed_callbacks':[i for i in r['callbackIds']if i not in excluded],'excluded_callbacks':[i for i in r['callbackIds']if i in excluded]}for r in selectors['selectors']if any(i in excluded for i in r['callbackIds'])]


def adapt_files(original,base):
 result={}
 name='Modules/LobbySharingAPI.cs';eol=newline(base[name]);start=b'public static class LobbySharingAPI';end=newline(original[name])+b'[SuppressMessage('
 body=with_newline(span(original[name],start,end),eol)
 replacement=encoded('''// The optional EHR directory is unavailable in the account-protected profile.
// Keep this original public surface for unrelated lifecycle callers. There is
// no credential read, HTTP request, token, queue or external response parser.
public static class LobbySharingAPI
{
    public static long LastRequestTimeStamp;
    public static string LastRoomCode = string.Empty;
    public static void NotifyLobbyStatusChanged(LobbyStatus status) { }
}

''',eol)
 result[name]=once(base[name],body,replacement)
 if b'EOSManager'in result[name]or b'UnityWebRequest'in result[name]:raise ValueError('Credential/network producer remains in protected lobby directory source')
 name='Modules/OptionHolder.cs';eol=newline(base[name]);text=base[name]
 before=encoded('''PostLobbyCodeToEHRWebsite = new BooleanOptionItem(19422, "PostLobbyCodeToEHRDiscordServer", true, TabGroup.SystemSettings)
            .SetHeader(true);''',eol)
 after=encoded('''PostLobbyCodeToEHRWebsite = new EHRProtectedLobbyDirectoryOption(19422, "PostLobbyCodeToEHRDiscordServer", TabGroup.SystemSettings)
            .SetHeader(true);''',eol)
 text=once(text,before,after)
 before=encoded('''LobbyUpdateInterval = new IntegerOptionItem(19502, "LobbyUpdateInterval", new(10, 30, 5), 30, TabGroup.SystemSettings)
            .SetParent(PostLobbyCodeToEHRWebsite)
            .SetValueFormat(OptionFormat.Seconds);''',eol)
 after=before[:-1]+encoded('\n            .SetHidden(true);',eol);result[name]=once(text,before,after)
 name='Modules/OptionItem/OptionItem.cs';eol=newline(base[name])
 before=encoded('''    public string GetName(bool disableColor = false, bool console = false)
    {''',eol)
 after=before+encoded('\n        if (this is EHRProtectedLobbyDirectoryOption) return EHRProtectedLobbyDirectoryOption.Label;',eol);result[name]=once(base[name],before,after)
 name='Patches/ChatCommandPatch.cs';eol=newline(base[name]);start=b'    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)';end=b'    public static void RetributeCommand('
 before=with_newline(span(original[name],start,end),eol);after=encoded('''    private static void ConfirmAuthCommand(PlayerControl player, string text, string[] args)
    {
        Utils.SendMessage(EHRProtectedLobbyDirectoryOption.UnavailableMessage, player.PlayerId);
    }

''',eol);text=once(base[name],before,after)
 start=b'    private static void LevelCommand(PlayerControl player, string text, string[] args)';end=b'    private static void HideNameCommand('
 before=with_newline(span(original[name],start,end),eol);after=encoded('''    private static void LevelCommand(PlayerControl player, string text, string[] args)
    {
        Utils.SendMessage(LEVEL_MESSAGE, player.PlayerId);
    }

'''.replace('LEVEL_MESSAGE',json.dumps(LEVEL_MESSAGE)),eol);result[name]=once(text,before,after)
 own='''// Original protected-profile option. Existing presets cannot enable this row.
namespace EHR;
internal sealed class EHRProtectedLobbyDirectoryOption : TextOptionItem
{
    internal const string Label = LABEL;
    internal const string UnavailableMessage = MESSAGE;
    internal EHRProtectedLobbyDirectoryOption(int id, string name, TabGroup tab)
        : base(id, name, tab, 0, true) { }
    public override int GetValue() => 0;
    public override void SetValue(int value, bool doSync = true) { }
    public override string GetString() => "Unavailable";
}
'''.replace('LABEL',json.dumps(LABEL)).replace('MESSAGE',json.dumps(MESSAGE))
 result['EHRProtectedLobbyDirectoryOption.cs']=own.encode()
 return result


def main(argv=None):
 parser=argparse.ArgumentParser(description=__doc__)
 for arg in('upstream','dispatcher-audit','selectors','output'):parser.add_argument('--'+arg,type=Path,required=True)
 parser.add_argument('--source-overlay',type=Path,help='Optional composed source; exact protected spans must still match pinned source')
 args=parser.parse_args(argv);repo=args.upstream.resolve();output=args.output.resolve();policy=json.loads(POLICY.read_text())
 if output.exists()or any((p/'.git').exists()for p in(output,*output.parents)):parser.error('Output must be a new outside-Git directory')
 if subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()!=policy['upstream_commit']or subprocess.check_output(['git','-C',str(repo),'status','--porcelain'],text=True):parser.error('Requires the exact clean pinned upstream checkout')
 for name,expected in policy['source_sha256'].items():
  if sha((repo/name).read_bytes())!=expected:parser.error('Source content differs from reviewed account-policy pin: '+name)
 audit=json.loads(args.dispatcher_audit.read_text());selectors=json.loads(args.selectors.read_text());selection=validate_descriptors(policy,audit,selectors)
 names=('Modules/LobbySharingAPI.cs','Modules/OptionHolder.cs','Modules/OptionItem/OptionItem.cs','Patches/ChatCommandPatch.cs');original={n:(repo/n).read_bytes()for n in names}
 base={n:((args.source_overlay/n).read_bytes()if args.source_overlay and(args.source_overlay/n).exists()else original[n])for n in names};adapted=adapt_files(original,base)
 output.mkdir(parents=True);rows=[]
 for name,data in adapted.items():
  path=output/'source'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);rows.append({'file':name,'input_sha256':sha(base[name])if name in base else None,'adapted_sha256':sha(data)})
 (output/'EHRSourceAccountPolicy.cs').write_text(policy_source(policy));(output/'account-protection-policy.json').write_text(json.dumps(policy,indent=2)+'\n')
 report={'schema':'ehr.source-account-protection-adaptation.v1','upstream_commit':policy['upstream_commit'],'profile':policy['profile'],'excluded_callback_count':len(policy['excluded_callbacks']),'per_selector_policy':selection,'adapted_files':rows,'public_lobby_directory_members_preserved':['LastRequestTimeStamp:Int64','LastRoomCode:String','NotifyLobbyStatusChanged(LobbyStatus):Void'],'own_option_default':False,'own_option19422_force_false_after_legacy_load':True,'directory_ui_label':LABEL,'level_command':{'recognized':True,'response':LEVEL_MESSAGE,'native_level_write_removed':True},'official_authentication_or_networking_modified':False,'broad_lifecycle_callbacks_removed':False,'tool_account_or_network_operations':0,'actual_runtime_tested_by_tool':False,'supplemental_sources':['EHRSourceAccountPolicy.cs','source/EHRProtectedLobbyDirectoryOption.cs']}
 (output/'account-protection-adaptation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'output':str(output),'excluded_callbacks':len(policy['excluded_callbacks']),'adapted_sources':len(adapted),'official_authentication_or_networking_modified':False},indent=2))


if __name__=='__main__':main()
