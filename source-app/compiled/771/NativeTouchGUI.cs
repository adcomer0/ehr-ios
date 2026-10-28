using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace EHR.Generated;

// Local presentation types for the ClientControlGUI iOS source adaptation.
// They are intentionally not UnityEngine.GUI/GUIStyle replacement facades.
public sealed class TouchTexture
{
    internal TouchState Fill;
    public TouchTexture(int width,int height,int radius,UnityEngine_Color fill,UnityEngine_Color edge)
    {
        if(width<1||height<1||radius<0)throw new ArgumentOutOfRangeException();
        Fill.fill=TouchColor.Read(fill); Fill.edge=TouchColor.Read(edge);
        Fill.radius=Math.Min(radius,Math.Min(width,height)/2f);
    }
}
public sealed class TouchGUIStyleState
{
    internal TouchState Value;
    public TouchTexture? background { set { if(value is null){Value.fill=default;Value.edge=default;Value.radius=0;}else{Value.fill=value.Fill.fill;Value.edge=value.Fill.edge;Value.radius=value.Fill.radius;} } }
    public UnityEngine_Color textColor { set=>Value.text=TouchColor.Read(value); }
}
public sealed class TouchGUIStyle
{
    public readonly TouchGUIStyleState normal=new(),hover=new(),active=new();
    public int fontSize; public UnityEngine_FontStyle fontStyle;
    public UnityEngine_TextAnchor alignment; public bool wordWrap,richText;
    public float fixedWidth;
    internal TouchStyle Snapshot(TouchColor tint)=>new(){normal=normal.Value,hover=hover.Value,active=active.Value,fontSize=fontSize,fontStyle=(int)fontStyle,alignment=(int)alignment,wordWrap=wordWrap?1:0,richText=richText?1:0,tint=tint};
}
public sealed class TouchGUISkin
{
    public readonly TouchGUIStyle verticalScrollbar=new(),verticalScrollbarThumb=new();
}
[StructLayout(LayoutKind.Sequential)] internal struct TouchColor
{
    internal float r,g,b,a;
    internal static TouchColor Read(UnityEngine_Color c)=>new(){r=Math.Clamp(c.r,0,1),g=Math.Clamp(c.g,0,1),b=Math.Clamp(c.b,0,1),a=Math.Clamp(c.a,0,1)};
}
[StructLayout(LayoutKind.Sequential)] internal struct TouchRect
{
    internal float x,y,width,height;
    internal static TouchRect Read(UnityEngine_Rect r)=>new(){x=r.x,y=r.y,width=r.width,height=r.height};
}
[StructLayout(LayoutKind.Sequential)] internal struct TouchState { internal TouchColor text,fill,edge;internal float radius; }
[StructLayout(LayoutKind.Sequential)] internal struct TouchStyle
{
    internal TouchState normal,hover,active;internal float fontSize;
    internal int fontStyle,alignment,wordWrap,richText;internal TouchColor tint;
}
[StructLayout(LayoutKind.Sequential)] internal struct TouchItem
{
    internal ulong key;internal uint kind,flags;internal TouchRect rect;
    internal float value,minimum,maximum;internal TouchStyle style;
}
[StructLayout(LayoutKind.Sequential)] internal struct TouchFrame
{
    internal uint version,size,shouldDraw,reserved;
    internal float px,py,width,height,safeLeft,safeTop,safeRight,safeBottom;
}
[StructLayout(LayoutKind.Sequential)] public unsafe struct TouchUIV1
{
    public uint Version,Size;
    internal delegate* unmanaged[Cdecl]<int> IsMainThread;
    internal delegate* unmanaged[Cdecl]<float,float,TouchFrame*,int> Begin;
    internal delegate* unmanaged[Cdecl]<int,int> End;
    internal delegate* unmanaged[Cdecl]<TouchItem*,byte*,nuint,float*,int*,int> Item;
    internal delegate* unmanaged[Cdecl]<ulong,TouchRect*,TouchRect*,float,float,float,float,float*,float*,int> BeginScroll;
    internal delegate* unmanaged[Cdecl]<int> EndScroll;
    internal delegate* unmanaged[Cdecl]<TouchRect*,float,int> MoveWindow;
    internal delegate* unmanaged[Cdecl]<int> Hide;
}
public static unsafe class TouchGUI
{
    private static TouchUIV1 table;
    private static bool bound,drawing,scrolling;
    private static ulong scope;
    private static readonly Dictionary<ulong,uint> occurrences=new();
    private static TouchColor tint=new(){r=1,g=1,b=1,a=1};
    private static UnityEngine_Color? nativeTint;
    private static readonly TouchGUIStyle sliderStyle=new(){alignment=default};
    public static TouchGUISkin skin {get;}=new();
    public static float PixelsPerPoint {get;private set;}=1;
    public static float PixelsPerPointX {get;private set;}=1;
    // Logical presentation facts from the last real native frame; no new ABI.
    public static float SafeWidth => viewport.width > 0 ? Math.Max(1, viewport.width-viewport.safeLeft-viewport.safeRight) : float.MaxValue;
    public static float SafeHeight => viewport.height > 0 ? Math.Max(1, viewport.height-viewport.safeTop-viewport.safeBottom) : float.MaxValue;
    public static float SafeLeft => viewport.safeLeft;
    public static float SafeTop => viewport.safeTop;
    private static TouchFrame viewport;
    // This property is local presentation state; the supplied real Color is read
    // through the facade and never reinterpreted as a guessed native struct.
    public static UnityEngine_Color color {get=>nativeTint??=new UnityEngine_Color(1,1,1,1);set{tint=TouchColor.Read(value);nativeTint=value;}}
    [UnmanagedCallersOnly(EntryPoint="ehr_touch_ui_bind_v1",CallConvs=new[]{typeof(CallConvCdecl)})]
    public static int Bind(TouchUIV1* host,nuint bytes)
    {
        if(host==null||bytes!=(nuint)sizeof(TouchUIV1)||host->Version!=1||host->Size!=sizeof(TouchUIV1)||host->IsMainThread==null||host->Begin==null||host->End==null||host->Item==null||host->BeginScroll==null||host->EndScroll==null||host->MoveWindow==null||host->Hide==null)return 4;
        if(bound||host->IsMainThread()!=1)return 4;
        table=*host;bound=true;return 0;
    }
    private static void Ready(){if(!bound)throw new PlatformNotSupportedException("Native iOS touch renderer is not bound.");if(table.IsMainThread()!=1)throw new InvalidOperationException("Touch controls require the Unity main thread.");}
    private static void Check(int status){if(status!=0)throw new InvalidOperationException($"iOS touch renderer status {status}.");}
    public static bool BeginFrame(float width,float height)
    {
        Ready();if(drawing)throw new InvalidOperationException("Nested touch frame.");
        TouchFrame frame=default;Check(table.Begin(width,height,&frame));
        if(frame.version!=1||frame.size!=sizeof(TouchFrame)||frame.px<=0||frame.py<=0)throw new InvalidOperationException("Invalid touch viewport.");
        PixelsPerPoint=frame.py;PixelsPerPointX=frame.px;viewport=frame;
        if(frame.shouldDraw==0)return false;
        occurrences.Clear();scope=0;drawing=true;scrolling=false;tint=new(){r=1,g=1,b=1,a=1};nativeTint=null;return true;
    }
    public static void EndFrame(bool commit)
    {
        if(!drawing)return;drawing=false;scrolling=false;scope=0;Check(table.End(commit?1:0));
    }
    public static void Hide(){Ready();drawing=false;scrolling=false;Check(table.Hide());}
    public static void MoveWindow(ref UnityEngine_Rect rect,float titleHeight)
    {
        if(!drawing)throw new InvalidOperationException("No touch frame.");
        TouchRect r=TouchRect.Read(rect);Check(table.MoveWindow(&r,titleHeight));
        r.width=Math.Min(r.width,Math.Max(1,viewport.width-viewport.safeLeft-viewport.safeRight));
        r.height=Math.Min(r.height,Math.Max(1,viewport.height-viewport.safeTop-viewport.safeBottom));
        ClampToSafeArea(ref r.x,ref r.y,r.width,r.height);
        Check(table.MoveWindow(&r,titleHeight));
        rect=new UnityEngine_Rect(r.x,r.y,r.width,r.height);
    }
    public static void ClampToSafeArea(ref float x,ref float y,float width,float height)
    {
        x=Math.Clamp(x,viewport.safeLeft,Math.Max(viewport.safeLeft,viewport.width-viewport.safeRight-width));
        y=Math.Clamp(y,viewport.safeTop,Math.Max(viewport.safeTop,viewport.height-viewport.safeBottom-height));
    }
    private static ulong Key(uint kind,string label,int line)
    {
        ulong hash=14695981039346656037UL;
        void Mix(uint v){hash=(hash^v)*1099511628211UL;}
        Mix(kind);Mix((uint)line);Mix((uint)scope);Mix((uint)(scope>>32));
        foreach(char c in label)Mix(c);
        occurrences.TryGetValue(hash,out uint occurrence);occurrences[hash]=occurrence+1;Mix(occurrence);return hash==0?1:hash;
    }
    private static float Emit(UnityEngine_Rect rect,string label,TouchGUIStyle style,uint kind,float value,float minimum,float maximum,int line,out bool pressed)
    {
        if(!drawing)throw new InvalidOperationException("No touch frame.");
        byte[] utf8=Encoding.UTF8.GetBytes(label);if(utf8.Length>8192)throw new ArgumentOutOfRangeException(nameof(label));
        TouchItem item=new(){key=Key(kind,kind==4?"":label,line),kind=kind,rect=TouchRect.Read(rect),value=value,minimum=minimum,maximum=maximum,style=style.Snapshot(tint)};
        int clicked=0;float result=0;fixed(byte* bytes=utf8)Check(table.Item(&item,bytes,(nuint)utf8.Length,&result,&clicked));pressed=clicked==1;return result;
    }
    public static bool Button(UnityEngine_Rect rect,string text,TouchGUIStyle style,[CallerLineNumber]int line=0){Emit(rect,text,style,3,0,0,0,line,out bool clicked);return clicked;}
    public static void Label(UnityEngine_Rect rect,string text,TouchGUIStyle style,[CallerLineNumber]int line=0)=>Emit(rect,text,style,2,0,0,0,line,out _);
    public static void Box(UnityEngine_Rect rect,string text,TouchGUIStyle style,[CallerLineNumber]int line=0)=>Emit(rect,text,style,1,0,0,0,line,out _);
    public static float HorizontalSlider(UnityEngine_Rect rect,float value,float minimum,float maximum,[CallerLineNumber]int line=0)=>Emit(rect,"",sliderStyle,4,value,minimum,maximum,line,out _);
    public static UnityEngine_Vector2 BeginScrollView(UnityEngine_Rect outer,UnityEngine_Vector2 position,UnityEngine_Rect inner,bool horizontal,bool vertical,[CallerLineNumber]int line=0)
    {
        if(!drawing||scrolling||horizontal||vertical)throw new InvalidOperationException("Only the source's automatic vertical scroll region is supported.");
        TouchRect a=TouchRect.Read(outer),b=TouchRect.Read(inner);float x=0,y=0;ulong key=Key(5,"scroll",line);Check(table.BeginScroll(key,&a,&b,position.x,position.y,skin.verticalScrollbar.fixedWidth,skin.verticalScrollbarThumb.fixedWidth,&x,&y));scrolling=true;scope=key;return new UnityEngine_Vector2(x,y);
    }
    public static void EndScrollView(){if(!scrolling)throw new InvalidOperationException("No scroll region.");Check(table.EndScroll());scrolling=false;scope=0;}
    [UnmanagedCallersOnly(EntryPoint="ehr_touch_ui_managed_contract_test",CallConvs=new[]{typeof(CallConvCdecl)})]
    public static int ContractTest(int* proof,nuint count)
    {
        if(proof==null||count<8)return 4;
        for(int i=0;i<8;i++)proof[i]=0;
        if(drawing)return 4;
        proof[1]=bound&&table.IsMainThread()==1?1:0;
        proof[2]=sizeof(TouchUIV1)==72?1:0;
        proof[3]=sizeof(TouchFrame)==48?1:0;
        proof[4]=sizeof(TouchItem)==240&&sizeof(TouchStyle)==192?1:0;
        proof[5]=RuntimeFeature.IsDynamicCodeSupported||RuntimeFeature.IsDynamicCodeCompiled?1:0;
        // Pure key contract: same context is stable; a different action label
        // cannot consume a pending event belonging to the old action.
        occurrences.Clear();scope=0;ulong first=Key(3,"Host action A",71);
        occurrences.Clear();ulong again=Key(3,"Host action A",71);
        occurrences.Clear();ulong other=Key(3,"Host action B",71);
        proof[6]=first==again&&first!=other?1:0;
        occurrences.Clear();scope=0;proof[7]=!drawing?1:0;
        proof[0]=proof[1]&proof[2]&proof[3]&proof[4]&proof[6]&proof[7];
        if(proof[5]!=0)proof[0]=0;
        return proof[0]==1?0:7;
    }
}
