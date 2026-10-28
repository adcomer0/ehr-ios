using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using EHR.Generated;
// Own value inputs only. No Unity/game object, native game API or scene exists.
namespace EHR.Generated
{
 public struct UnityEngine_Color {public float r,g,b,a;public UnityEngine_Color(float r,float g,float b,float a){this.r=r;this.g=g;this.b=b;this.a=a;}public static UnityEngine_Color white=>new(1,1,1,1);}
 public struct UnityEngine_Rect {public float x,y,width,height;public UnityEngine_Rect(float x,float y,float width,float height){this.x=x;this.y=y;this.width=width;this.height=height;}}
 public struct UnityEngine_Vector2 {public float x,y;public UnityEngine_Vector2(float x,float y){this.x=x;this.y=y;}}
 public enum UnityEngine_FontStyle {Normal,Bold,Italic,BoldAndItalic}
 public enum UnityEngine_TextAnchor {UpperLeft,UpperCenter,UpperRight,MiddleLeft,MiddleCenter,MiddleRight,LowerLeft,LowerCenter,LowerRight}
}
internal static class GeometryMath
{
 internal static float Max(float a,float b)=>Math.Max(a,b);internal static int Max(int a,int b)=>Math.Max(a,b);
 internal static float Min(float a,float b)=>Math.Min(a,b);internal static int RoundToInt(float value)=>(int)MathF.Round(value);
 internal static float Clamp01(float value)=>Math.Clamp(value,0,1);
}
internal static class GeometryPlatform {internal static bool IsAndroid()=>false;}
internal static class GeometryViewport {internal static int width,height;}
static unsafe class Program
{
 internal record struct Emission(TouchRect Rect,uint Kind,TouchStyle Style,bool Scrolling);
 internal static List<Emission> Items=new();internal static TouchRect Outer;
 private static float px=1,py=1,left,top,right,bottom;private static bool scrolling;
 private static int checks,scenarios;
 static void Assert(bool value,string message){checks++;if(!value)throw new Exception(message+" ["+checks+"]");}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int IsMain()=>1;
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int Begin(float w,float h,TouchFrame*f){*f=new(){version=1,size=48,shouldDraw=1,px=px,py=py,width=w,height=h,safeLeft=left*px,safeTop=top*py,safeRight=right*px,safeBottom=bottom*py};return 0;}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int End(int commit)=>0;
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int Item(TouchItem*i,byte*b,nuint n,float*v,int*p){Items.Add(new(i->rect,i->kind,i->style,scrolling));*v=i->value;*p=0;return 0;}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int Scroll(ulong k,TouchRect*a,TouchRect*b,float x,float y,float w,float thumb,float*ox,float*oy){Outer=*a;scrolling=true;*ox=*oy=0;return 0;}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int EndScroll(){scrolling=false;return 0;}
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int Move(TouchRect*r,float height)=>0;
 [UnmanagedCallersOnly(CallConvs=new[]{typeof(CallConvCdecl)})]static int Hide()=>0;
 static bool Near(float a,float b)=>Math.Abs(a-b)<0.02f;
 static void InSafe(TouchRect r,string name)
 {
  Assert(r.x/px>=left-0.02f&&r.y/py>=top-0.02f,name+" starts in safe area");
  Assert((r.x+r.width)/px<=GeometryViewport.width/px-right+0.02f&&(r.y+r.height)/py<=GeometryViewport.height/py-bottom+0.02f,name+" ends in safe area");
 }
 static void Draw(SourceGeometry source,bool open)
 {
  Items.Clear();Assert(TouchGUI.BeginFrame(GeometryViewport.width,GeometryViewport.height),"frame available");
  Assert(Near(TouchGUI.PixelsPerPointX,px)&&Near(TouchGUI.PixelsPerPoint,py),"real frame density retained");
  Assert(Near(TouchGUI.SafeWidth,GeometryViewport.width-(left+right)*px),"safe pixel width retained");
  source.Run(open);TouchGUI.EndFrame(true);
  foreach(var item in Items)
  {
   if(item.Kind is 2 or 3)Assert(item.Style.fontSize/py>=14-0.001f,"readable client text");
   if(item.Kind is 3 or 4){Assert(item.Rect.width/px>=44-0.001f,"touch width >=44pt");Assert(item.Rect.height/py>=44-0.001f,"touch height >=44pt");}
   if(!item.Scrolling)InSafe(item.Rect,"top-level control");
  }
  if(open){InSafe(Outer,"scroll viewport");Assert(Outer.width/px>=44&&Outer.height/py>=44,"scroll viewport usable");}
 }
 static void Main()
 {
  TouchUIV1 host=new(){Version=1,Size=72,IsMainThread=&IsMain,Begin=&Begin,End=&End,Item=&Item,BeginScroll=&Scroll,EndScroll=&EndScroll,MoveWindow=&Move,Hide=&Hide};
  delegate* unmanaged[Cdecl]<TouchUIV1*,nuint,int> bind=&TouchGUI.Bind;Assert(bind(&host,72)==0,"table bound");Assert(TouchGUI.PixelsPerPoint==1&&TouchGUI.PixelsPerPointX==1,"pre-frame fallback");
  var cases=new(float w,float h,float l,float t,float r,float b)[]{(667,375,44,0,44,21),(852,393,59,0,59,21),(956,440,62,0,62,21),(393,852,0,59,0,34),(1024,768,0,24,0,20),(1366,1024,0,24,0,20),(768,1024,0,24,0,20)};
  var densities=new(float x,float y)[]{(1,1),(2,2),(3,3),(1.5f,1.5f),(2.5f,3),(3,2.5f)};
  foreach(var c in cases)foreach(var density in densities)
  {
   scenarios++;px=density.x;py=density.y;left=c.l;top=c.t;right=c.r;bottom=c.b;GeometryViewport.width=(int)MathF.Round(c.w*px);GeometryViewport.height=(int)MathF.Round(c.h*py);
   var source=new SourceGeometry();Draw(source,false);Assert(source.Rebuilds==1,"first successful frame rebuilds once");Draw(source,true);Assert(source.Rebuilds==1,"unchanged frame preserves styles");
   source.DragTo(100000,100000);Draw(source,true);var before=source.Rect;Assert(Near(before.x+before.width,GeometryViewport.width-right*px)&&Near(before.y+before.height,GeometryViewport.height-bottom*py),"drag clamped to bottom-right");
   px*=1.25f;py*=1.25f;GeometryViewport.width=(int)MathF.Round(c.w*px);GeometryViewport.height=(int)MathF.Round(c.h*py);Draw(source,true);Assert(source.Rebuilds==2,"density change reflows styles/window");
   var after=source.Rect;Assert(Math.Abs(before.width/density.x-after.width/px)<0.75f&&Math.Abs(before.height/density.y-after.height/py)<0.75f,"window remains point-sized within one render-pixel rounding after density change");
   float oldLeft=left;left=right;right=oldLeft+5;Draw(source,true);Assert(source.Rebuilds==3,"safe area change reflows geometry");
   int oldWidth=GeometryViewport.width;GeometryViewport.width=GeometryViewport.height;GeometryViewport.height=oldWidth;left=right=0;top=24;bottom=20;Draw(source,true);Assert(source.Rebuilds==4,"rotation reflows geometry");
  }
  Console.WriteLine("{\"actualTransformedGeometryChecks\":"+checks+",\"deviceDensityScenarios\":"+scenarios+",\"engineInvoked\":false,\"minimumControlPoints\":44,\"minimumTextPoints\":14,\"tableBytes\":"+sizeof(TouchUIV1)+"}");
 }
}
