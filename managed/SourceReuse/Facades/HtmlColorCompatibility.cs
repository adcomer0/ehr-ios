using System;
namespace EHR.Generated;

// Independent compatibility implementation for an engine helper stripped from
// this game. Contract: Unity 2022.3 ColorUtility.TryParseHtmlString API docs.
// https://docs.unity3d.com/2022.3/Documentation/ScriptReference/ColorUtility.TryParseHtmlString.html
// This computes RGBA bytes only; the facade constructs a genuine native Color.
internal static class HtmlColorCompatibility
{
    internal static bool Parse(string? text,out uint rgba)
    {
        rgba=0;
        if(string.IsNullOrEmpty(text))return false;
        if(text[0]!='#')
        {
            uint? named=text.ToLowerInvariant() switch
            {
                "red"=>0xFF0000FFu,"cyan" or "aqua"=>0x00FFFFFFu,
                "blue"=>0x0000FFFFu,"darkblue"=>0x00008BFFu,
                "lightblue"=>0xADD8E6FFu,"purple"=>0x800080FFu,
                "yellow"=>0xFFFF00FFu,"lime"=>0x00FF00FFu,
                "fuchsia" or "magenta"=>0xFF00FFFFu,"white"=>0xFFFFFFFFu,
                "silver"=>0xC0C0C0FFu,"grey"=>0x808080FFu,
                "black"=>0x000000FFu,"orange"=>0xFFA500FFu,
                "brown"=>0xA52A2AFFu,"maroon"=>0x800000FFu,
                "green"=>0x008000FFu,"olive"=>0x808000FFu,
                "navy"=>0x000080FFu,"teal"=>0x008080FFu,_=>null
            };
            if(!named.HasValue)return false;
            rgba=named.Value;return true;
        }
        int digits=text.Length-1;
        if(digits!=3&&digits!=4&&digits!=6&&digits!=8)return false;
        uint value=0;
        for(int i=1;i<text.Length;++i)
        {
            char c=text[i];
            int nibble=c>='0'&&c<='9'?c-'0':c>='A'&&c<='F'?c-'A'+10:c>='a'&&c<='f'?c-'a'+10:-1;
            if(nibble<0)return false;
            value=digits<=4?(value<<8)|(uint)(nibble*17):(value<<4)|(uint)nibble;
        }
        rgba=digits==3||digits==6?(value<<8)|255u:value;
        return true;
    }
}
