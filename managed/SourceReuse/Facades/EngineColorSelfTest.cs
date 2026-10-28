using System;
using System.Runtime.InteropServices;
namespace EHR.Generated;
internal static unsafe class EngineColorSelfTest
{
    private static bool Case(string input,string expected)
    {
        if(!UnityEngine_ColorUtility.TryParseHtmlString(input,out var color))return false;
        using var box=color.NativeBox;
        NativeArgument argument=NativeValues.Argument(box);
        using var text=FacadeRuntime.Invoke(new("UnityEngine.CoreModule.dll","UnityEngine","ColorUtility","ToHtmlStringRGBA",true,false,"System.String",["UnityEngine.Color"]),0,&argument,1);
        return FacadeRuntime.ReadString(text)==expected;
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_generated_engine_color_self_test")]
    internal static int Run(int* output,nuint count)
    {
        if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
        try
        {
            (string Input,string Output)[] named=[("rEd","FF0000FF"),("cyan","00FFFFFF"),("blue","0000FFFF"),("darkblue","00008BFF"),("lightblue","ADD8E6FF"),("purple","800080FF"),("yellow","FFFF00FF"),("lime","00FF00FF"),("fuchsia","FF00FFFF"),("white","FFFFFFFF"),("silver","C0C0C0FF"),("grey","808080FF"),("black","000000FF"),("orange","FFA500FF"),("brown","A52A2AFF"),("maroon","800000FF"),("green","008000FF"),("olive","808000FF"),("navy","000080FF"),("teal","008080FF"),("aqua","00FFFFFF"),("magenta","FF00FFFF")];
            bool namedPassed=true;foreach(var item in named)namedPassed=Case(item.Input,item.Output)&&namedPassed;
            output[2]=namedPassed?1:0;
            output[3]=Case("#F0A","FF00AAFF")&&Case("#F0A7","FF00AA77")&&Case("#fF00807f","FF00807F")&&Case("#123456","123456FF")?1:0;
            bool invalid=UnityEngine_ColorUtility.TryParseHtmlString("not-a-color",out var invalidColor);
            using var invalidBox=invalidColor.NativeBox;output[4]=!invalid&&FacadeRuntime.TokenIsValid(invalidBox.Token)?1:0;
            foreach(string malformed in new[]{"","#","#12","#12345","#1234567","#123456789","#GGG","#１２３"})
            {
                bool accepted=UnityEngine_ColorUtility.TryParseHtmlString(malformed,out var value);
                using var valueBox=value.NativeBox;if(accepted)output[4]=0;
            }
            bool nullResult=UnityEngine_ColorUtility.TryParseHtmlString(null,out var nullColor);
            using var nullBox=nullColor.NativeBox;output[5]=!nullResult&&FacadeRuntime.TokenIsValid(nullBox.Token)?1:0;
            output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;return output[1]=output[0]==1?0:5;
        }
        catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
    }
}
