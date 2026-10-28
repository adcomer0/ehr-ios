using EHR.Generated;
namespace EHR.NativeProbes;
// Original own source type, same native metadata identity as the real probe.
public sealed class StaticLifecycleProbe:UnityEngine_MonoBehaviour
{
    internal static int ConstructorCount,TotalAwake,TotalUpdate,TotalDestroy,TotalPing;
    internal static System.WeakReference<StaticLifecycleProbe>? Last;
    private static int Initialize(){++ConstructorCount;return 37;}
    internal readonly int Initialized=Initialize();
    internal int AwakeCount,UpdateCount,DestroyCount,PingCount;
    private void Awake(){++AwakeCount;++TotalAwake;Last=new(this);}
    private void Update(){++UpdateCount;++TotalUpdate;}
    private void OnDestroy(){++DestroyCount;++TotalDestroy;}
    private void Ping(){++PingCount;++TotalPing;}
    internal void Dispatch(uint message)
    {
        switch(message){case 1:Awake();break;case 2:Update();break;case 3:OnDestroy();break;case 4:Ping();break;
            default:throw new RuntimeGatewayException(7,"unknown source probe message");}
    }
}
