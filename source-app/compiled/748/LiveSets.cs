using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace EHR.Generated
{
    internal static unsafe class NativeSetCalls
    {
        internal static ulong Class<T>()=>LiveReflection.MakeGenericClass(FacadeRuntime.Class("System.Core.dll","System.Collections.Generic","HashSet`1"),[ElementCodecs.Get<T>().NativeClass()]);
        internal static RuntimeObject NoArgs<T>(RuntimeObject set,string name,string result)
        {
            ulong method=NativeMethods.Lookup(Class<T>(),name,[],FacadeRuntime.Class("mscorlib.dll","System",result),false);
            return FacadeRuntime.InvokeResolved(method,set.Token,null,0);
        }
        internal static bool One<T>(RuntimeObject set,string name,T value)
        {
            ulong method=NativeMethods.Lookup(Class<T>(),name,[ElementCodecs.Get<T>().NativeClass()],ElementCodecs.Get<bool>().NativeClass(),false);
            using var boxed=ElementCodecs.Get<T>().Box(value);
            using var invocation=NativeReflectedCall.InvokeResolved(method,set.Token,[boxed]);
            using var result=invocation.TakeResult();return FacadeRuntime.ReadValue<bool>(result);
        }
        internal static bool ReadOnly<T>(RuntimeObject set)
        {
            ulong owner=LiveReflection.MakeGenericClass(FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","ICollection`1"),[ElementCodecs.Get<T>().NativeClass()]);
            ulong method=NativeMethods.Lookup(owner,"get_IsReadOnly",[],ElementCodecs.Get<bool>().NativeClass(),false);
            using var result=FacadeRuntime.InvokeResolved(method,set.Token,null,0);return FacadeRuntime.ReadValue<bool>(result);
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_set_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if(output==null||count!=6)return 4;for(int i=0;i<6;++i)output[i]=0;
            try
            {
                using var strings=new Il2CppSystem.Collections.Generic.HashSet<string>();
                output[2]=strings.Add("A\0\U0001F680")&&!strings.Add("A\0\U0001F680")&&strings.Add("other")&&strings.Count==2&&strings.Contains("A\0\U0001F680")?1:0;
                int seen=0;foreach(string text in strings)if(text=="A\0\U0001F680"||text=="other")++seen;
                using var numbers=new Il2CppSystem.Collections.Generic.HashSet<int>();
                output[3]=seen==2&&numbers.Add(11)&&numbers.Contains(11)&&!numbers.Contains(12)&&numbers.Count==1?1:0;
                output[4]=strings.Remove("other")&&!strings.Remove("other")&&strings.Count==1?1:0;
                strings.Clear();output[4]=output[4]==1&&strings.Count==0?1:0;
                using var list=new Il2CppSystem.Collections.Generic.List<int>([1,2,3,4]);
                list.RemoveRange(1,2);output[5]=list.Count==2&&list[0]==1&&list[1]==4?1:0;
                output[0]=output[2]==1&&output[3]==1&&output[4]==1&&output[5]==1?1:0;return output[1]=output[0]==1?0:5;
            }
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
        }
    }
}
namespace Il2CppSystem.Collections.Generic
{
    public class HashSet<T>:Il2CppSystem.Object,ICollection<T>,IReadOnlyCollection<T>
    {
        internal static ulong NativeClass=>EHR.Generated.NativeSetCalls.Class<T>();
        public HashSet():base(EHR.Generated.LiveReflection.Construct(NativeClass,[]).Detach()){}
        public HashSet(IEnumerable<T> values):this(){try{foreach(T value in values)Add(value);}catch{Dispose();throw;}}
        internal HashSet(ulong owned,bool takeOwnership):base(owned){}
        public int Count {get{using var result=EHR.Generated.NativeSetCalls.NoArgs<T>(this,"get_Count","Int32");return EHR.Generated.FacadeRuntime.ReadValue<int>(result);}}
        public bool IsReadOnly=>EHR.Generated.NativeSetCalls.ReadOnly<T>(this);
        public bool Add(T value)=>EHR.Generated.NativeSetCalls.One(this,"Add",value);
        void ICollection<T>.Add(T value)=>Add(value);
        public bool Contains(T value)=>EHR.Generated.NativeSetCalls.One(this,"Contains",value);
        public bool Remove(T value)=>EHR.Generated.NativeSetCalls.One(this,"Remove",value);
        public void Clear(){using var result=EHR.Generated.NativeSetCalls.NoArgs<T>(this,"Clear","Void");}
        public void CopyTo(T[] values,int index)
        {ArgumentNullException.ThrowIfNull(values);if(index<0||index>values.Length||values.Length-index<Count)throw new ArgumentOutOfRangeException(nameof(index));foreach(T value in this)values[index++]=value;}
        public IEnumerator<T> GetEnumerator()=>new Cursor(EHR.Generated.NativeDictionaryCalls.Enumerate(this,false).Detach());
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()=>GetEnumerator();
        private sealed class Cursor:IEnumerator<T>
        {
            private readonly Il2CppSystem.Collections.IEnumerator native;
            internal Cursor(ulong owned){native=new(owned);}
            public bool MoveNext()=>native.MoveNext();public void Reset()=>native.Reset();
            public T Current {get{using var value=native.Current;return (T)EHR.Generated.ElementCodecs.Get<T>().Read(value is null?new EHR.Generated.RuntimeObject(0):EHR.Generated.FacadeRuntime.Retain(value))!;}}
            object? System.Collections.IEnumerator.Current=>Current;
            public void Dispose()=>native.Dispose();
        }
    }
}
