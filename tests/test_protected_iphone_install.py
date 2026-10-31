from pathlib import Path
import importlib.util
import json
import plistlib
import tempfile
import sys
import unittest
from contextlib import redirect_stderr
import io
from unittest.mock import patch
from types import SimpleNamespace

STAGE = Path(__file__).resolve().parents[1]
CANONICAL = STAGE
TEAM = 'ABCDEFGHIJ'
BUNDLE = 'org.example.ehrfixture'
sys.path.insert(0, str(STAGE/'tools'))
try:
    spec = importlib.util.spec_from_file_location('protected_install', STAGE/'tools/install_protected_iphone.py')
    M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
finally:
    sys.path.pop(0)
runtime, _ = M.helpers(CANONICAL)
OWN_DEVICE = '11111111-1111-1111-1111-111111111111'
OWN_UDID = '01234567-0123456789ABCDEF'


def receipt(command, result):
    return {'info': {'outcome':'success','commandType':'devicectl.'+command}, 'result':result}


class OwnDeviceRunner:
    def __init__(self, disconnected=False, *, absent=False, product_type='iPhone18,2'):
        self.calls=[]; self.disconnected=disconnected;self.absent=absent;self.product_type=product_type
    def call(self, name, arguments, seconds=20):
        self.calls.append((name,arguments))
        hardware={'udid':OWN_UDID,'productType':self.product_type,'platform':'iOS'}
        connection={'pairingState':'paired','transportType':'localNetwork','tunnelState':'connected'}
        if name=='device-inventory':
            return receipt('list.devices', {'devices':[] if self.disconnected else
                [{'identifier':OWN_DEVICE,'hardwareProperties':hardware,'connectionProperties':connection}]})
        if name=='device-details':
            return receipt('device.info.details', {'identifier':OWN_DEVICE,'hardwareProperties':hardware,
                'connectionProperties':connection,'deviceProperties':{'bootState':'booted',
                'developerModeStatus':'enabled','ddiServicesAvailable':True}})
        if name in ('installed-before','installed-after'):
            return receipt('device.info.apps', {'deviceIdentifier':OWN_DEVICE,'matchingBundleIdentifier':BUNDLE,
                'apps':[] if self.absent and name=='installed-before' else
                    [{'bundleIdentifier':BUNDLE,'bundleVersion':'24.1' if name.endswith('before') else '36',
                      'version':'1.0','url':'file:///Own/Installed.app'}]})
        if name=='install':
            return receipt('device.install.app', {'deviceIdentifier':OWN_DEVICE,'installedApplications':[{'bundleID':BUNDLE}]})
        if name=='launch':
            return receipt('device.process.launch', {'deviceIdentifier':OWN_DEVICE,
                'launchOptions':{'activatedWhenStarted':True,'startStopped':False,
                    'terminateExistingInstances':False,'arguments':[],'environmentVariables':{'TERM':'dumb'}},
                'process':{'processIdentifier':42,'executable':'file:///Own/Installed.app/EHRNativeGame'}})
        if name=='processes':
            return receipt('device.info.processes', {'deviceIdentifier':OWN_DEVICE,
                'runningProcesses':[{'processIdentifier':42,'executable':'file:///Own/Installed.app/EHRNativeGame'}]})
        raise AssertionError('Unexpected operation: '+name)


class InstallerGuards(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='ehr-own-installer-')
        self.root=Path(self.temporary.name); self.app=self.root/'Own.app';self.app.mkdir()
        for relative in runtime.RELATIVE_BINARIES:
            target=self.app/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(('Own fixture '+relative).encode())
        (self.app/'embedded.mobileprovision').write_bytes(b'Own fixture profile, not a real profile')
        info={'CFBundleIdentifier':BUNDLE,'CFBundleExecutable':'EHRNativeGame',
              'CFBundleVersion':'36','CFBundleShortVersionString':'1.0','EHRReferenceGameVersion':'1.0','UIDeviceFamily':[1,2]}
        (self.app/'Info.plist').write_bytes(plistlib.dumps(info))
        mac=self.root/'Mac';mac.mkdir();(mac/'RuntimeResults.xcresult').mkdir();(mac/'Attachments').mkdir()
        summary={'destination':{'platform':'macOS','physical_device':False},'xcodebuild_exit_code':0,
            'source_candidate_unchanged':True,'terms_or_ui_actions_performed':False,'diagnostic_install_attempted':False,
            'result_bundle':str(mac/'RuntimeResults.xcresult'),'attachments':str(mac/'Attachments'),
            'candidate_binary_sha256':{p:runtime.hash_file(self.app/p) for p in runtime.RELATIVE_BINARIES},
            'candidate_profile_sha256':runtime.hash_file(self.app/'embedded.mobileprovision')}
        self.summary=mac/'runtime-test-summary.json'; self.summary.write_text(json.dumps(summary))
        self.proof=mac/'Attachments/EHRNativeXCTestProof.json'
        self.proof.write_text(json.dumps({'schema':'ehr.full-source-startup-proof.v1',
            'applicationVersion':{'success':True,'status':0,'value':'1.0','expected':'1.0'},
            'startupReachedTerminalObservation':True,'termsAcceptedByTest':False,'accountActionsPerformed':False,
            'status':{'status':0,'attempted':True,'fullMainLoadRequested':True,'productionCoroutinesReady':True,
                      'bindingsReady':True,'stage':'source_callbacks_active','application':{'state':3,'status':0,
                      'dynamicCodeFlags':0,'optionsLoaded':1,'postLoadTasksComplete':1,
                      'activeBindings':7,'optionCount':12,'unavailableTargets':0}}}))
        (mac/'test.log').write_text('Own fixture terminal\n** TEST EXECUTE SUCCEEDED **\n')
        self.signing={'signature_verified':True,'team_id':TEAM,'bundle_id':BUNDLE,
            'build':'36','version':'1.0','requested_device_covered':True}
        (mac/'signing-before.json').write_text(json.dumps(self.signing))
        self.device=self.root/'destination.local.json';self.device.write_text(json.dumps({'udid':OWN_UDID,'deviceIdentifier':OWN_DEVICE}))
        self.output=self.root/'Output';self.output.mkdir();self.verified=[]
    def tearDown(self):self.temporary.cleanup()
    def verifier(self,app,udid,**expected):
        if expected:self.assertEqual(expected,dict(team_id=TEAM,bundle_id=BUNDLE,team_name=None))
        self.assertEqual(app,self.app);self.assertEqual(udid,OWN_UDID);self.verified.append(udid)
        return dict(self.signing)
    def run_fixture(self,runner,**options):
        summary={'status':'not_started','installation_succeeded':False}
        return M.execute(self.app,self.summary,self.device,self.output,runtime,self.verifier,runner,summary,team_id=TEAM,bundle_id=BUNDLE,**options)

    def enable_game_start_adapter(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes())
        info['EHRGameStartIteratorCompiled']=True;path.write_bytes(plistlib.dumps(info))
        proof=json.loads(self.proof.read_text());proof['status']['gameStartIterator']={'preparedStatus':0,'enabled':True}
        self.proof.write_text(json.dumps(proof))

    def write_game_start_proof(self,**changes):
        proof={'schema':'ehr.game-start-iterator-proof.v1','success':True,'status':0,'stage':0,
            'checks':46,'factorySeamCalls':6,'rootsBefore':12,'rootsAfter':12,'rootAccountingBalanced':True,
            'deferredReleasedBefore':100,'deferredReleasedAfter':100,'deferredEnqueuedBefore':100,
            'deferredEnqueuedAfter':100,'deferredDequeuedBefore':100,'deferredDequeuedAfter':100,
            'cancelCallsBefore':1,'cancelCallsAfter':2,'fixtureNullOwner':True,'realGameOwnerInvoked':False,
            'originalMoveNextInvoked':False,'realHostFactoryInvoked':False,'unityObjectCreated':False,
            'runtimeExecutableWrites':False}
        proof.update(changes)
        path=self.proof.with_name('EHRGameStartIteratorProof.json');path.write_text(json.dumps(proof))
        return path

    def enable_auth_handoff(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes())
        info['EHRAuthHandoffDiagnosticsCompiled']=True;path.write_bytes(plistlib.dumps(info))
        proof=json.loads(self.proof.read_text());proof['status']['authHandoff']={'preparedStatus':0,'schemaVersion':2,
            'eventCapacity':32,'eventCount':0,'events':[],
            'appleSuccesses':0,'managedCredentialEntries':0,'loginEntries':0,'typeObservations':0,'observerFaults':0}
        self.proof.write_text(json.dumps(proof))

    def write_auth_handoff_proof(self,**changes):
        proof={'schema':'ehr.auth-handoff-proof.v1','success':True,'status':0,'preparedStatus':0,'checks':87,'failures':0,
            'eventCapacity':32,'eventRingBounded':True,'middleAppleTypePreserved':True,'unknownScalarRedacted':True,
            'isolatedRecorder':True,'realAuthenticationInvoked':False,'credentialsRead':False,'networkOperations':False,
            'runtimeExecutableWrites':False,'actualCredentialReads':0,'originalAuthCalls':0,'networkRequests':0,'accountActions':0}
        proof.update(changes)
        path=self.proof.with_name('EHRAuthHandoffProof.json');path.write_text(json.dumps(proof))
        return path

    def test_changed_binary_or_profile_rejected_before_any_device_operation(self):
        for path in (runtime.RELATIVE_BINARIES[2], 'embedded.mobileprovision'):
            target=self.app/path;before=target.read_bytes();target.write_bytes(before+b'changed')
            runner=OwnDeviceRunner()
            with self.subTest(path=path),self.assertRaises(ValueError):self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[]);target.write_bytes(before)

    def test_wrong_or_unobserved_unity_version_rejected_before_device_access(self):
        before=self.proof.read_text();proof=json.loads(before)
        for version in ({}, {'success':True,'status':0,'value':'0.0.0','expected':'1.0'},
                        {'success':False,'status':6,'value':'1.0','expected':'1.0'}):
            proof['applicationVersion']=version;self.proof.write_text(json.dumps(proof))
            runner=OwnDeviceRunner()
            with self.subTest(version=version),self.assertRaisesRegex(M.Rejected,'actual_game_runtime_version'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])
        self.proof.write_text(before)

    def test_enabled_eos_observer_requires_passed_actual_preparation(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes());info['EHREOSLoginDiagnosticsEnabled']=True
        path.write_bytes(plistlib.dumps(info));original=json.loads(self.proof.read_text())
        for status in (None, 1, 3, 7):
            proof=json.loads(json.dumps(original))
            if status is not None:proof['status']['eosLoginObserverStatus']=status
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(status=status),self.assertRaisesRegex(M.Rejected,'eos_login_observer_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])

    def enable_itch_provider(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes())
        info.update(EHRItchAuthCompiled=True,EHRAuthProvider='itchio',EHRItchOwnershipRequired=True);path.write_bytes(plistlib.dumps(info))
        proof=json.loads(self.proof.read_text())
        native=dict(preparedStatus=0,enabled=True,sdkLoginCalls=0,completionCount=0,
                    originalSuccessCalls=0,originalFailureCalls=0,resultKnown=False,pending=False,fullGameCompleted=False,
                    newUserMigrationChecks=0,newUserMigrationRejections=0,newUserMigrationStatus=1,
                    awaitingNewUserConfirmation=False,continuityAvailable=False,originalCallbackDelivered=False,continuedNewUser=False,newUserMigrationValidated=False)
        proof['status']['itchAuthentication']=dict(selected=True,preparedStatus=0,runtime=native,clearedForRestart=False,credentialEpoch=0,credentialClears=0,
            ownershipStatus=6,ownershipHTTPStatus=0,ownershipChecks=0,ownershipVerified=False,ownershipPending=False,directoryAllowed=False,
            awaitingNativeLogin=False,nativeLoginWaitSeconds=0,ownershipResponse={})
        self.proof.write_text(json.dumps(proof))
        own=dict(schema='ehr.itch-auth-marshal-proof.v1',success=True,status=0,
                 ownResultPreserved=True,rootsBefore=4,rootsAfter=4,realLoginInvoked=False,
                 existingManagerAvailable=True,delegateFactoryStatus=0,
                 originalSilentDelegateFactoryPassed=True,gameOwnerConstructed=False,
                 gameCallbackInvoked=False,credentialRead=False,accountCreation=False,accountLinking=False)
        self.proof.with_name('EHRItchAuthProof.json').write_text(json.dumps(own))

    def test_itch_provider_requires_ready_and_untouched_startup_before_device_access(self):
        self.enable_itch_provider();baseline=json.loads(self.proof.read_text())
        for changes in ({'preparedStatus':1},{'enabled':False},{'sdkLoginCalls':1},
                        {'resultKnown':True},{'pending':True},{'fullGameCompleted':True},
                        {'originalSuccessCalls':1},{'preparedStatus':False},
                        {'newUserMigrationChecks':1},{'newUserMigrationRejections':1},
                        {'newUserMigrationStatus':0},{'newUserMigrationStatus':True},
                        {'awaitingNewUserConfirmation':True},{'continuityAvailable':True},
                        {'originalCallbackDelivered':True},{'continuedNewUser':True},{'newUserMigrationValidated':True}):
            proof=json.loads(json.dumps(baseline));proof['status']['itchAuthentication']['runtime'].update(changes)
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(changes=changes),self.assertRaisesRegex(M.Rejected,'itch_provider_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])
        self.proof.write_text(json.dumps(baseline));runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])
        for changes in ({'clearedForRestart':True},{'credentialEpoch':1},{'credentialClears':1},{'credentialClears':False},
                        {'ownershipVerified':True},{'ownershipPending':True},{'directoryAllowed':True},
                        {'awaitingNativeLogin':True},{'awaitingNativeLogin':0},
                        {'nativeLoginWaitSeconds':1},{'nativeLoginWaitSeconds':False},{'nativeLoginWaitSeconds':-1},
                        {'ownershipChecks':1},{'ownershipChecks':False},{'ownershipHTTPStatus':200},
                        {'ownershipStatus':True},{'ownershipStatus':-1},{'ownershipStatus':12},
                        {'ownershipResponse':None},{'ownershipResponse':[]},{'ownershipResponse':{'parserStage':7}}):
            proof=json.loads(json.dumps(baseline));proof['status']['itchAuthentication'].update(changes)
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(changes=changes),self.assertRaisesRegex(M.Rejected,'itch_provider_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])

    def test_directory_requires_bound_default_deny_before_device_access(self):
        self.enable_itch_provider()
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes());info['EHRDirectoryCompiled']=True;path.write_bytes(plistlib.dumps(info))
        baseline=json.loads(self.proof.read_text())
        for directory in ({},{'compiled':True,'bound':False,'allowed':False},{'compiled':True,'bound':True,'allowed':True},
                          {'compiled':True,'bound':True,'allowed':False,'ticks':1,'tickStatus':0},
                          {'compiled':True,'bound':True,'allowed':False,'ticks':0,'tickStatus':True}):
            proof=json.loads(json.dumps(baseline));proof['status']['websiteDirectory']=directory;self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(directory=directory),self.assertRaisesRegex(M.Rejected,'ehr_directory_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])
        baseline['status']['websiteDirectory']=dict(compiled=True,bound=True,allowed=False,ticks=0,tickStatus=0);self.proof.write_text(json.dumps(baseline));runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])

    def test_itch_provider_rejects_missing_or_actionful_marshal_proof_before_device_access(self):
        self.enable_itch_provider();path=self.proof.with_name('EHRItchAuthProof.json');original=json.loads(path.read_text())
        path.unlink();runner=OwnDeviceRunner()
        with self.assertRaisesRegex(M.Rejected,'itch_marshal_proof_missing'):self.run_fixture(runner)
        self.assertEqual(runner.calls,[])
        for changes in ({'success':False},{'status':True},{'ownResultPreserved':False},
                        {'existingManagerAvailable':False},{'delegateFactoryStatus':False},
                        {'delegateFactoryStatus':7},{'originalSilentDelegateFactoryPassed':False},
                        {'gameOwnerConstructed':True},
                        {'rootsAfter':3},{'rootsAfter':True},{'realLoginInvoked':True},
                        {'gameCallbackInvoked':True},{'credentialRead':True},
                        {'accountCreation':True},{'accountLinking':True}):
            path.write_text(json.dumps(dict(original,**changes)));runner=OwnDeviceRunner()
            with self.subTest(changes=changes),self.assertRaisesRegex(M.Rejected,'itch_marshal_proof_not_passed'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])

    def test_network_disconnect_scalar_capture_requires_untouched_mac_startup(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes());info['EHRNetworkDiagnosticsCompiled']=True
        path.write_bytes(plistlib.dumps(info));original=json.loads(self.proof.read_text())
        ready={'schemaVersion':1,'targetMatches':0,'count':0,'hasReason':0,'observerFaults':0}
        for network in (None,{},dict(ready,schemaVersion=0),dict(ready,count=1),
                        dict(ready,targetMatches=1),dict(ready,hasReason=1),dict(ready,observerFaults=1)):
            proof=json.loads(json.dumps(original));proof['status']['numericDiagnostics']={'networkDisconnect':network}
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(network=network),self.assertRaisesRegex(M.Rejected,'network_disconnect_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])
        proof=json.loads(json.dumps(original));proof['status']['numericDiagnostics']={'networkDisconnect':ready}
        self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory'])

    def test_requested_auth_guard_requires_actual_prepared_enabled_startup_before_device_access(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes())
        info['EHRAuthRetryGuardActivationRequested']=True;info['EHRAuthRetryGuardCompiled']=True
        path.write_bytes(plistlib.dumps(info));original=json.loads(self.proof.read_text())
        ready={'startupRequested':True,'preparedStatus':0,'startupPrepareStatus':0,'startupEnableStatus':0,'enabled':True}
        cases=[None,{},dict(ready,startupRequested=False),dict(ready,preparedStatus=1),
               dict(ready,startupPrepareStatus=5),dict(ready,startupEnableStatus=7),dict(ready,enabled=False)]
        for guard in cases:
            proof=json.loads(json.dumps(original))
            if guard is not None:proof['status']['authRetryGuard']=guard
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(guard=guard),self.assertRaisesRegex(M.Rejected,'auth_retry_guard_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])
        proof=json.loads(json.dumps(original));proof['status']['authRetryGuard']=ready
        self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner(disconnected=True)
        summary=self.run_fixture(runner,preflight_only=True)
        self.assertIn('unreachable',summary['status']);self.assertEqual([c[0]for c in runner.calls],['device-inventory'])

    def test_auth_handoff_requires_passed_preparation_without_auth_actions_before_device_access(self):
        self.enable_auth_handoff();self.write_auth_handoff_proof();original=json.loads(self.proof.read_text())
        ready=original['status']['authHandoff']
        for handoff in (None,{},dict(ready,preparedStatus=1),dict(ready,preparedStatus=False),
                        dict(ready,observerFaults=1),dict(ready,loginEntries=1),dict(ready,typeObservations=1)):
            proof=json.loads(json.dumps(original));proof['status']['authHandoff']=handoff
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(handoff=handoff),self.assertRaisesRegex(M.Rejected,'auth_handoff_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])

    def test_auth_handoff_requires_isolated_numeric_probe_before_device_access(self):
        self.enable_auth_handoff();runner=OwnDeviceRunner()
        with self.assertRaisesRegex(M.Rejected,'auth_handoff_self_test_missing'):self.run_fixture(runner)
        self.assertEqual(runner.calls,[])
        for values in ({'schema':'own.unrelated-proof'},{'success':False},{'status':6},{'checks':86},
                       {'eventCapacity':33},{'eventRingBounded':False},{'middleAppleTypePreserved':False},
                       {'preparedStatus':1},{'failures':1},{'originalAuthCalls':1},{'accountActions':1},
                       {'runtimeExecutableWrites':True},{'actualCredentialReads':1},{'networkRequests':1},
                       {'checks':True},{'isolatedRecorder':False},{'realAuthenticationInvoked':True},
                       {'credentialsRead':True},{'networkOperations':True}):
            self.write_auth_handoff_proof(**values);runner=OwnDeviceRunner()
            with self.subTest(values=values),self.assertRaisesRegex(M.Rejected,'auth_handoff_self_test_not_passed'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])
        self.write_auth_handoff_proof();runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory'])

    def test_compiled_game_start_adapter_requires_ready_enabled_actual_startup_before_device_access(self):
        path=self.app/'Info.plist';info=plistlib.loads(path.read_bytes())
        info['EHRGameStartIteratorCompiled']=True;path.write_bytes(plistlib.dumps(info))
        original=json.loads(self.proof.read_text());ready={'preparedStatus':0,'enabled':True}
        for adapter in (None,{},dict(ready,preparedStatus=1),dict(ready,enabled=False)):
            proof=json.loads(json.dumps(original))
            if adapter is not None:proof['status']['gameStartIterator']=adapter
            self.proof.write_text(json.dumps(proof));runner=OwnDeviceRunner()
            with self.subTest(adapter=adapter),self.assertRaisesRegex(M.Rejected,'game_start_iterator_startup_not_ready'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[])
        proof=json.loads(json.dumps(original));proof['status']['gameStartIterator']=ready
        self.proof.write_text(json.dumps(proof));self.write_game_start_proof();runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory'])

    def test_compiled_game_start_adapter_rejects_absent_or_invalid_self_test_before_device_access(self):
        self.enable_game_start_adapter();runner=OwnDeviceRunner()
        with self.assertRaisesRegex(M.Rejected,'game_start_iterator_self_test_missing'):self.run_fixture(runner)
        self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])
        path=self.proof.with_name('EHRGameStartIteratorProof.json')
        for content in ('{', '[]', '{}', 'null'):
            path.write_text(content);runner=OwnDeviceRunner()
            with self.subTest(content=content),self.assertRaisesRegex(M.Rejected,'game_start_iterator_self_test'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])

    def test_compiled_game_start_adapter_rejects_failed_incomplete_or_actionful_probe(self):
        self.enable_game_start_adapter()
        cases=[{'schema':'own.unrelated-proof'}, {'success':False}, {'status':6}, {'status':False}, {'stage':1},
               {'checks':45}, {'checks':True}, {'factorySeamCalls':5}, {'cancelCallsAfter':1},
               {'rootAccountingBalanced':False}, {'fixtureNullOwner':False}]
        for flag in ('realGameOwnerInvoked','originalMoveNextInvoked','realHostFactoryInvoked',
                     'unityObjectCreated','runtimeExecutableWrites'):
            cases.extend(({flag:True},{flag:None}))
        for values in cases:
            self.write_game_start_proof(**values);runner=OwnDeviceRunner()
            with self.subTest(values=values),self.assertRaisesRegex(M.Rejected,'game_start_iterator_self_test'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])

    def test_compiled_game_start_adapter_verifies_actual_root_and_deferred_counts(self):
        self.enable_game_start_adapter()
        for values in ({'rootsAfter':13}, {'rootsBefore':None}, {'deferredReleasedAfter':99},
                       {'deferredEnqueuedAfter':99}, {'deferredDequeuedAfter':99},
                       {'deferredReleasedAfter':101}, {'rootsAfter':'12'}, {'rootsBefore':-1}):
            self.write_game_start_proof(**values);runner=OwnDeviceRunner()
            with self.subTest(values=values),self.assertRaisesRegex(M.Rejected,'game_start_iterator_self_test'):
                self.run_fixture(runner)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])
        self.write_game_start_proof(rootsAfter=10,deferredReleasedAfter=102,
                                   deferredDequeuedAfter=102,deferredEnqueuedAfter=102)
        runner=OwnDeviceRunner(disconnected=True)
        self.assertIn('unreachable',self.run_fixture(runner,preflight_only=True)['status'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory'])

    def test_failed_or_non_full_startup_and_wrong_paid_team_are_rejected(self):
        before=self.proof.read_text();proof=json.loads(before)
        proof['status']['application']['optionsLoaded']=0;self.proof.write_text(json.dumps(proof))
        runner=OwnDeviceRunner()
        with self.assertRaisesRegex(M.Rejected,'full_startup'):self.run_fixture(runner)
        self.assertEqual(runner.calls,[]);self.proof.write_text(before)
        self.signing['team_id']='OWNINVALID'
        with self.assertRaisesRegex(M.Rejected,'exact_phone_paid_signature'):self.run_fixture(runner)
        self.assertEqual(runner.calls,[])

    def test_foreign_nested_binary_team_is_rejected(self):
        expected=SimpleNamespace(stderr='TeamIdentifier='+TEAM+'\n')
        foreign=SimpleNamespace(stderr='TeamIdentifier=OWNINVALID\n')
        with patch.object(M.subprocess,'run',side_effect=[expected,foreign]):
            with self.assertRaisesRegex(M.Rejected,'tested_binary_signing_team'):
                M.verify_candidate(self.app,OWN_UDID,runtime,self.verifier,team_id=TEAM,bundle_id=BUNDLE)

    def test_unreachable_preflight_is_honest_and_never_installs(self):
        runner=OwnDeviceRunner(disconnected=True);summary=self.run_fixture(runner,preflight_only=True)
        self.assertIn('unreachable',summary['status']);self.assertFalse(summary['installation_succeeded'])
        self.assertEqual([c[0] for c in runner.calls],['device-inventory'])
        self.assertEqual(self.verified,[OWN_UDID]);self.assertNotIn(OWN_UDID,json.dumps(summary))
        self.assertNotIn(OWN_DEVICE,json.dumps(summary))

    def test_upgrade_and_plain_launch_use_exact_bundle_without_uninstall_or_container_access(self):
        runner=OwnDeviceRunner();summary=self.run_fixture(runner,launch=True)
        self.assertEqual(summary['status'],'upgrade_installed_and_launched');self.assertTrue(summary['process_observed_running'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory','device-details','installed-before','install','installed-after','launch','processes'])
        for name,args in runner.calls:
            self.assertNotIn('uninstall',args);self.assertNotIn('copy',args);self.assertNotIn('--terminate-existing',args)
            self.assertNotIn('--include-container-paths',args)
            if name.startswith('installed-'):self.assertEqual(args[-2:],['--bundle-id',BUNDLE])
        self.assertNotIn(OWN_DEVICE,json.dumps(summary));self.assertNotIn(OWN_UDID,json.dumps(summary))
        launch=OwnDeviceRunner().call('launch',[])
        launch['result']['launchOptions']['environmentVariables']['OWN_EXTRA_OVERRIDE']='1'
        with self.assertRaisesRegex(M.Rejected,'plain_foreground'):
            M.validate_launch(launch,OWN_DEVICE,{'url':'file:///Own/Installed.app'})

    def test_upgrade_only_rejects_same_or_newer_installed_build_and_foreign_receipts(self):
        original=OwnDeviceRunner.call
        for existing in ('36','37','36.1'):
            class ExistingRunner(OwnDeviceRunner):
                def call(inner,name,args,seconds=20):
                    value=original(inner,name,args,seconds)
                    if name=='installed-before':value['result']['apps'][0]['bundleVersion']=existing
                    return value
            runner=ExistingRunner();summary=self.run_fixture(runner)
            self.assertEqual(summary['status'],'candidate_build_not_newer')
            self.assertNotIn('install',[c[0]for c in runner.calls])
        class MissingRunner(OwnDeviceRunner):
            def call(inner,name,args,seconds=20):
                value=original(inner,name,args,seconds)
                if name=='installed-before':value['result']['apps']=[]
                return value
        missing=MissingRunner();summary=self.run_fixture(missing)
        self.assertEqual(summary['status'],'upgrade_requires_existing_exact_app')
        self.assertNotIn('install',[c[0]for c in missing.calls])
        wrong=receipt('device.info.apps',{'deviceIdentifier':OWN_DEVICE,'matchingBundleIdentifier':BUNDLE,
            'apps':[{'bundleIdentifier':'own.foreign.app'}]})
        with self.assertRaisesRegex(M.Rejected,'installed_bundle'):M.installed_app(wrong,OWN_DEVICE,bundle_id=BUNDLE)

    def test_explicit_initial_install_requires_absence_and_never_launches_or_queries_other_apps(self):
        runner=OwnDeviceRunner(absent=True);summary=self.run_fixture(runner,initial_install=True)
        self.assertEqual(summary['status'],'initial_install_installed');self.assertTrue(summary['initial_install_ready'])
        self.assertTrue(summary['installed_version_confirmed']);self.assertNotIn('previous_build',summary)
        self.assertEqual(summary['install_mode'],'initial_install')
        self.assertEqual([c[0]for c in runner.calls],['device-inventory','device-details','installed-before','install','installed-after'])
        for name,args in runner.calls:
            self.assertNotIn('uninstall',args);self.assertNotIn('copy',args);self.assertNotIn('launch',args)
            self.assertNotIn('--include-container-paths',args)
            if name.startswith('installed-'):self.assertEqual(args[-2:],['--bundle-id',BUNDLE])
        self.assertNotIn(OWN_DEVICE,json.dumps(summary));self.assertNotIn(OWN_UDID,json.dumps(summary))
        existing=OwnDeviceRunner();summary=self.run_fixture(existing,initial_install=True)
        self.assertEqual(summary['status'],'initial_install_requires_absent_exact_app')
        self.assertNotIn('install',[c[0]for c in existing.calls])

    def test_initial_install_preflight_and_launch_conflict_are_nonmutating(self):
        runner=OwnDeviceRunner(absent=True);summary=self.run_fixture(runner,initial_install=True,preflight_only=True)
        self.assertEqual(summary['status'],'ready_for_initial_install');self.assertFalse(summary['installation_succeeded'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory','device-details','installed-before'])
        runner=OwnDeviceRunner(absent=True);self.verified.clear()
        with self.assertRaisesRegex(M.Rejected,'initial_install_never_launches'):
            self.run_fixture(runner,initial_install=True,launch=True)
        self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])
        output=self.root/'UntouchedCLIOutput'
        args=['--source-root',str(CANONICAL),'--candidate-app',str(self.app),
              '--mac-runtime-summary',str(self.summary),'--device-id-file',str(self.device),
              '--output-root',str(output),'--team-id',TEAM,'--bundle-id',BUNDLE,
              '--initial-install','--launch']
        with redirect_stderr(io.StringIO()),self.assertRaises(SystemExit) as error:M.main(args)
        self.assertEqual(error.exception.code,2);self.assertFalse(output.exists())

    def test_initial_install_keeps_exact_profile_coverage_and_installed_version_proof(self):
        runner=OwnDeviceRunner(absent=True);self.signing['requested_device_covered']=False
        with self.assertRaisesRegex(M.Rejected,'exact_phone_paid_signature'):
            self.run_fixture(runner,initial_install=True)
        self.assertEqual(runner.calls,[]);self.signing['requested_device_covered']=True
        original=OwnDeviceRunner.call
        class WrongInstalled(OwnDeviceRunner):
            def call(inner,name,args,seconds=20):
                value=original(inner,name,args,seconds)
                if name=='installed-after':value['result']['apps'][0]['bundleVersion']='35'
                return value
        runner=WrongInstalled(absent=True)
        with self.assertRaisesRegex(M.Rejected,'installed_version_not_confirmed'):
            self.run_fixture(runner,initial_install=True)
        self.assertEqual([c[0]for c in runner.calls],['device-inventory','device-details','installed-before','install','installed-after'])

    def test_explicit_exact_iphone_model_is_required_in_both_inventory_and_details(self):
        runner=OwnDeviceRunner(absent=True,product_type='iPhone17,1')
        summary=self.run_fixture(runner,initial_install=True,preflight_only=True,expected_product_type='iPhone17,1')
        self.assertEqual(summary['status'],'ready_for_initial_install');self.assertEqual(summary['expected_product_type'],'iPhone17,1')
        runner=OwnDeviceRunner(absent=True,product_type='iPhone17,1')
        self.assertIn('unreachable',self.run_fixture(runner,initial_install=True)['status'])
        self.assertEqual([c[0]for c in runner.calls],['device-inventory'])
        original=OwnDeviceRunner.call
        class WrongDetails(OwnDeviceRunner):
            def call(inner,name,args,seconds=20):
                value=original(inner,name,args,seconds)
                if name=='device-details':value['result']['hardwareProperties']['productType']='iPhone18,2'
                return value
        runner=WrongDetails(absent=True,product_type='iPhone17,1')
        with self.assertRaisesRegex(M.Rejected,'details_identity_differs'):
            self.run_fixture(runner,initial_install=True,expected_product_type='iPhone17,1')
        self.assertEqual([c[0]for c in runner.calls],['device-inventory','device-details'])
        for invalid in ('*','iPhone18,*','iPad13,*','iPhone018,2','iPhone18,0','iPad015,7','iPad15,0',None):
            runner=OwnDeviceRunner(absent=True);self.verified.clear()
            with self.subTest(model=invalid),self.assertRaisesRegex(M.Rejected,'expected_product_type'):
                self.run_fixture(runner,initial_install=True,expected_product_type=invalid)
            self.assertEqual(runner.calls,[]);self.assertEqual(self.verified,[])

    def test_explicit_exact_ipad_initial_install_preserves_no_launch_and_profile_gates(self):
        runner=OwnDeviceRunner(absent=True,product_type='iPad15,7')
        summary=self.run_fixture(runner,initial_install=True,expected_product_type='iPad15,7')
        self.assertEqual(summary['status'],'initial_install_installed')
        self.assertTrue(summary['installed_version_confirmed'])
        self.assertEqual([c[0] for c in runner.calls],['device-inventory','device-details','installed-before','install','installed-after'])
        self.assertNotIn('launch',[c[0] for c in runner.calls])
        runner=OwnDeviceRunner(absent=True,product_type='iPad15,7')
        self.assertIn('unreachable',self.run_fixture(runner,initial_install=True)['status'])
        self.signing['requested_device_covered']=False;runner=OwnDeviceRunner(absent=True,product_type='iPad15,7')
        with self.assertRaisesRegex(M.Rejected,'exact_phone_paid_signature'):
            self.run_fixture(runner,initial_install=True,expected_product_type='iPad15,7')
        self.assertEqual(runner.calls,[])

    def test_initial_install_rejects_ambiguous_identity_and_nonphysical_or_unpaired_inventory(self):
        original=OwnDeviceRunner.call
        for variant in ('duplicate_udid','duplicate_identifier','wrong_platform','unpaired','same_machine'):
            class InvalidInventory(OwnDeviceRunner):
                def call(inner,name,args,seconds=20):
                    value=original(inner,name,args,seconds)
                    if name=='device-inventory':
                        rows=value['result']['devices'];row=rows[0]
                        if variant.startswith('duplicate'):
                            extra=json.loads(json.dumps(row))
                            if variant=='duplicate_identifier':extra['hardwareProperties']['udid']='FEDCBA98-0123456789ABCDEF'
                            rows.append(extra)
                        elif variant=='wrong_platform':row['hardwareProperties']['platform']='macOS'
                        elif variant=='unpaired':row['connectionProperties']['pairingState']='unpaired'
                        else:row['connectionProperties']['transportType']='sameMachine'
                    return value
            runner=InvalidInventory(absent=True)
            with self.subTest(variant=variant):
                summary=self.run_fixture(runner,initial_install=True)
                self.assertIn('unreachable',summary['status']);self.assertEqual([c[0]for c in runner.calls],['device-inventory'])


if __name__=='__main__':unittest.main()
