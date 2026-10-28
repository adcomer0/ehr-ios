using System;
using System.Runtime.InteropServices;

namespace EHR.Generated
{
    internal static unsafe class NativeSystemTypes
    {
        internal static ulong QueueClass<T>()=>LiveReflection.MakeGenericClass(
            FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","Queue`1"),[ElementCodecs.Get<T>().NativeClass()]);
        internal static ulong FuncClass<T>()
        {
            if(typeof(T)!=typeof(bool))throw new RuntimeGatewayException(7,"native Func result shape unsupported");
            return LiveReflection.MakeGenericClass(FacadeRuntime.Class("mscorlib.dll","System","Func`1"),[ElementCodecs.Get<T>().NativeClass()]);
        }
        internal static RuntimeObject QueueCall<T>(RuntimeObject owner,string name,ulong resultClass,RuntimeObject? value=null)
        {
            ulong method=NativeMethods.Lookup(QueueClass<T>(),name,value is null?[]:[ElementCodecs.Get<T>().NativeClass()],resultClass,false);
            using var invocation=NativeReflectedCall.InvokeResolved(method,owner.Token,value is null?[]:[value]);
            return invocation.TakeResult();
        }
        internal static RuntimeObject BuilderCall(RuntimeObject owner,string name,string result,string[] parameters,RuntimeObject[] arguments)
        {
            BindingSpec spec=new("mscorlib.dll","System.Text","StringBuilder",name,false,false,result,parameters);
            using var invocation=NativeReflectedCall.Invoke(spec,owner.Token,arguments);
            return invocation.TakeResult();
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_system_types_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if(output==null||count!=7)return 4;for(int i=0;i<7;++i)output[i]=0;
            try
            {
                using var builder=new Il2CppSystem.Text.StringBuilder();
                using var append=builder.Append("A\0\U0001F680\r\nB");
                using var replace=builder.Replace("\r\n","\n");
                output[2]=builder.ToString()=="A\0\U0001F680\nB"&&NativeLifetime.Same(builder,append)&&NativeLifetime.Same(builder,replace)?1:0;
                using var queue=new Il2CppSystem.Collections.Generic.Queue<UnityEngine_Vector2>();
                queue.Enqueue(new(1.5f,-2.5f));queue.Enqueue(new(3f,4f));
                UnityEngine_Vector2 peek=queue.Peek();UnityEngine_Vector2 first=queue.Dequeue();
                output[3]=queue.Count==1&&peek.x==1.5f&&peek.y==-2.5f&&first.x==1.5f&&first.y==-2.5f?1:0;
                queue.Clear();output[4]=queue.Count==0?1:0;
                try { queue.Dequeue(); } catch(NativeGameException exception)
                {using(exception){using var original=exception.RetainNativeException();output[5]=FacadeRuntime.ObjectClass(original)==FacadeRuntime.Class("mscorlib.dll","System","InvalidOperationException")?1:0;}}
                ulong klass=FuncClass<bool>();
                output[6]=NativeMethods.Lookup(klass,"Invoke",[],ElementCodecs.Get<bool>().NativeClass(),false)!=0?1:0;
                output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1&&output[6]==1?1:0;
                return output[1]=output[0]==1?0:5;
            }
            catch(RuntimeGatewayException error){return output[1]=error.Status;}catch{return output[1]=6;}
        }
    }
}

namespace Il2CppSystem.Text
{
    // A real native StringBuilder, with its mutable buffer kept wholly IL2CPP-side.
    public sealed class StringBuilder:Il2CppSystem.Object
    {
        internal static ulong NativeClass=>EHR.Generated.FacadeRuntime.Class("mscorlib.dll","System.Text","StringBuilder");
        internal StringBuilder(ulong owned):base(owned){}
        public StringBuilder():base(EHR.Generated.NativeConstructors.Create(NativeClass,[],[])){}
        public StringBuilder Append(string? text)
        {
            using var value=EHR.Generated.FacadeRuntime.String(text);
            return new(EHR.Generated.NativeSystemTypes.BuilderCall(this,"Append","System.Text.StringBuilder",["System.String"],[value]).Detach());
        }
        public StringBuilder Replace(string oldValue,string? newValue)
        {
            using var oldText=EHR.Generated.FacadeRuntime.String(oldValue);using var newText=EHR.Generated.FacadeRuntime.String(newValue);
            return new(EHR.Generated.NativeSystemTypes.BuilderCall(this,"Replace","System.Text.StringBuilder",["System.String","System.String"],[oldText,newText]).Detach());
        }
        public override string? ToString()
        {
            using var result=EHR.Generated.NativeSystemTypes.BuilderCall(this,"ToString","System.String",[],[]);
            return EHR.Generated.FacadeRuntime.ReadString(result);
        }
    }
}

namespace Il2CppSystem.Collections.Generic
{
    public sealed class Queue<T>:Il2CppSystem.Object
    {
        internal static ulong NativeClass=>EHR.Generated.NativeSystemTypes.QueueClass<T>();
        internal Queue(ulong owned,bool takeOwnership):base(owned){}
        public Queue():base(EHR.Generated.LiveReflection.Construct(NativeClass,[]).Detach()){}
        public int Count
        {
            get{using var result=EHR.Generated.NativeSystemTypes.QueueCall<T>(this,"get_Count",EHR.Generated.ElementCodecs.Get<int>().NativeClass());return EHR.Generated.FacadeRuntime.ReadValue<int>(result);}
        }
        public void Enqueue(T value)
        {
            using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(value);
            using var result=EHR.Generated.NativeSystemTypes.QueueCall<T>(this,"Enqueue",EHR.Generated.FacadeRuntime.Class("mscorlib.dll","System","Void"),boxed);
        }
        public T Peek()=>Read("Peek");
        public T Dequeue()=>Read("Dequeue");
        private T Read(string name)=>(T)EHR.Generated.ElementCodecs.Get<T>().Read(EHR.Generated.NativeSystemTypes.QueueCall<T>(this,name,EHR.Generated.ElementCodecs.Get<T>().NativeClass()))!;
        public void Clear(){using var result=EHR.Generated.NativeSystemTypes.QueueCall<T>(this,"Clear",EHR.Generated.FacadeRuntime.Class("mscorlib.dll","System","Void"));}
    }
}

namespace Il2CppSystem
{
    // This wraps an EXISTING native delegate. There is deliberately no CLR Func
    // callback constructor: construction requires a separate proven native ABI.
    public sealed unsafe class Func<TResult>:Il2CppSystem.Object
    {
        internal static ulong NativeClass=>EHR.Generated.NativeSystemTypes.FuncClass<TResult>();
        internal Func(ulong owned):base(owned){}
        public TResult Invoke()
        {
            ulong method=EHR.Generated.NativeMethods.Lookup(NativeClass,"Invoke",[],EHR.Generated.ElementCodecs.Get<TResult>().NativeClass(),false);
            using var result=EHR.Generated.FacadeRuntime.InvokeResolved(method,Token,null,0);
            return (TResult)EHR.Generated.ElementCodecs.Get<TResult>().Read(result)!;
        }
    }
}
