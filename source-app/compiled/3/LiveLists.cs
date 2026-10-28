using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace EHR.Generated
{
    [StructLayout(LayoutKind.Sequential)]
    internal unsafe struct ReflectionTable
    {
        internal uint AbiVersion,ByteSize;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> ClassFromTypeObject;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,nuint,ulong*,ulong*,int> MakeGenericClass;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,nuint,ulong*,ulong*,int> Construct;
        internal delegate* unmanaged[Cdecl]<ulong,ulong*,int> InitializeClass;
    }
    internal static unsafe class LiveReflection
    {
        private static ReflectionTable table;
        private static bool bound;
        internal static void InitializeClass(ulong klass)
        {
            if(!bound)throw new RuntimeGatewayException(1,"reflection extensions not bound");
            ulong exception=0;int status=table.InitializeClass(klass,&exception);
            Check(status,exception,"caught class initialization");
        }
        internal static RuntimeObject Construct(ulong klass,RuntimeObject?[] arguments)
        {
            if(!bound)throw new RuntimeGatewayException(1,"reflection extensions not bound");
            if(arguments.Length>128)throw new ArgumentOutOfRangeException(nameof(arguments));
            ulong* tokens=stackalloc ulong[arguments.Length];
            for(int i=0;i<arguments.Length;++i)tokens[i]=arguments[i]?.Token??0;
            ulong result=0,exception=0;
            int status=table.Construct(klass,arguments.Length==0?null:tokens,(nuint)arguments.Length,&result,&exception);
            if(status!=0||exception!=0){FacadeRuntime.Release(result);Check(status,exception,"construct native object");}
            return new(result);
        }
        internal static ulong ClassFromTypeObject(RuntimeObject type)
        {
            if(!bound)throw new RuntimeGatewayException(1,"reflection extensions not bound");
            ulong klass=0;FacadeRuntime.Require(table.ClassFromTypeObject(type.Token,&klass),"class from real Type");return klass;
        }
        internal static ulong MakeGenericClass(ulong open,ReadOnlySpan<ulong> argumentClasses)
        {
            if(!bound)throw new RuntimeGatewayException(1,"reflection extensions not bound");
            ulong closed=0,exception=0;int status;
            fixed(ulong* arguments=argumentClasses)status=table.MakeGenericClass(open,arguments,(nuint)argumentClasses.Length,&closed,&exception);
            Check(status,exception,"make exact closed native class");return closed;
        }
        internal static ulong ListClass<T>()=>MakeGenericClass(FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","List`1"),[ElementCodecs.Get<T>().NativeClass()]);
        internal static ulong ConstructList<T>(int? capacity)
        {
            if(!bound)throw new RuntimeGatewayException(1,"reflection extensions not bound");
            ulong open=FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","List`1");
            ulong argument=ElementCodecs.Get<T>().NativeClass(),closed=0,exception=0;
            int status=table.MakeGenericClass(open,&argument,1,&closed,&exception);
            Check(status,exception,"make List<T> native class");
            ulong result=0;
            if(capacity is null)
            {
                status=table.Construct(closed,null,0,&result,&exception);
            }
            else
            {
                using var boxed=ElementCodecs.Get<int>().Box(capacity.Value);
                ulong capacityToken=boxed.Token;
                status=table.Construct(closed,&capacityToken,1,&result,&exception);
            }
            if(status!=0||exception!=0){FacadeRuntime.Release(result);Check(status,exception,"construct native List<T>");}
            return result;
        }
        private static void Check(int status,ulong exception,string operation)
        {
            FacadeRuntime.CheckManaged(status,exception,operation);
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_bind_reflection")]
        internal static int Bind(ReflectionTable* source,nuint size)
        {
            if(source==null||size!=(nuint)sizeof(ReflectionTable)||source->AbiVersion!=1||source->ByteSize!=sizeof(ReflectionTable))return 4;
            if(source->ClassFromTypeObject==null||source->MakeGenericClass==null||source->Construct==null||source->InitializeClass==null)return 4;
            table=*source;bound=true;return 0;
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_list_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if(output==null||count!=4)return 4;
            for(int i=0;i<4;++i)output[i]=0;
            try
            {
                using var list=new Il2CppSystem.Collections.Generic.List<int>();
                list.Add(11);list.Add(22);list[1]=23;
                bool changed=list.Count==2&&list[0]==11&&list[1]==23&&list.Contains(23)&&!list.Contains(22);
                changed=changed&&list.Remove(11)&&list.Count==1&&list[0]==23;
                list.Add(31);
                using(var array=list.ToArray())changed=changed&&array.Length==2&&array[0]==23&&array[1]==31;
                output[2]=changed?1:0;
                var iterator=list.GetEnumerator();bool began=iterator.MoveNext()&&iterator.Current==23;
                list.Add(99);
                try{iterator.MoveNext();output[3]=0;}catch(InvalidOperationException){output[3]=began?1:0;}
                iterator.Dispose();
                output[0]=output[2]==1&&output[3]==1?1:0;
                return output[1]=output[0]==1?0:5;
            }
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}
            catch{return output[1]=6;}
        }
    }
    internal static unsafe class NativeListCalls
    {
        private static BindingSpec Spec(string member,string result,string[] parameters,bool collection=false)
            =>new("mscorlib.dll","System.Collections",collection?"ICollection":"IList",member,false,false,result,parameters);
        internal static int Count(RuntimeObject list)
        {
            using var result=FacadeRuntime.Invoke(Spec("get_Count","System.Int32",[],true),list.Token,null,0);
            return FacadeRuntime.ReadValue<int>(result);
        }
        internal static bool IsReadOnly(RuntimeObject list)
        {
            using var result=FacadeRuntime.Invoke(Spec("get_IsReadOnly","System.Boolean",[]),list.Token,null,0);
            return FacadeRuntime.ReadValue<bool>(result);
        }
        internal static RuntimeObject Get(RuntimeObject list,int index)
        {
            NativeArgument argument=FacadeRuntime.Value(&index,"System.Int32");
            return FacadeRuntime.Invoke(Spec("get_Item","System.Object",["System.Int32"]),list.Token,&argument,1);
        }
        internal static void Set(RuntimeObject list,int index,RuntimeObject value)
        {
            NativeArgument* arguments=stackalloc NativeArgument[2];
            arguments[0]=FacadeRuntime.Value(&index,"System.Int32");arguments[1]=FacadeRuntime.Reference(value);
            using var result=FacadeRuntime.Invoke(Spec("set_Item","System.Void",["System.Int32","System.Object"]),list.Token,arguments,2);
        }
        internal static RuntimeObject ObjectCall(RuntimeObject list,string member,string resultType,RuntimeObject value)
        {
            NativeArgument argument=FacadeRuntime.Reference(value);
            return FacadeRuntime.Invoke(Spec(member,resultType,["System.Object"]),list.Token,&argument,1);
        }
        internal static void Insert(RuntimeObject list,int index,RuntimeObject value)
        {
            NativeArgument* arguments=stackalloc NativeArgument[2];
            arguments[0]=FacadeRuntime.Value(&index,"System.Int32");arguments[1]=FacadeRuntime.Reference(value);
            using var result=FacadeRuntime.Invoke(Spec("Insert","System.Void",["System.Int32","System.Object"]),list.Token,arguments,2);
        }
        internal static void RemoveAt(RuntimeObject list,int index)
        {
            NativeArgument argument=FacadeRuntime.Value(&index,"System.Int32");
            using var result=FacadeRuntime.Invoke(Spec("RemoveAt","System.Void",["System.Int32"]),list.Token,&argument,1);
        }
        internal static void Clear(RuntimeObject list)
        {using var result=FacadeRuntime.Invoke(Spec("Clear","System.Void",[]),list.Token,null,0);}
        internal static void CopyTo(RuntimeObject list,RuntimeObject array)
        {
            int index=0;
            NativeArgument* arguments=stackalloc NativeArgument[2];
            arguments[0]=FacadeRuntime.Reference(array);arguments[1]=FacadeRuntime.Value(&index,"System.Int32");
            using var result=FacadeRuntime.Invoke(Spec("CopyTo","System.Void",["System.Array","System.Int32"],true),list.Token,arguments,2);
        }
    }
}

namespace Il2CppSystem.Collections.Generic
{
    // This object is an owning facade over an actual game-runtime List<T>.
    // Every operation reaches IList/ICollection in that runtime. It never keeps
    // a second System.Collections.Generic.List<T> as the game collection's state.
    public class List<T>:Il2CppSystem.Object,System.Collections.Generic.IList<T>,IReadOnlyList<T>
    {
        internal static ulong NativeClass=>EHR.Generated.LiveReflection.ListClass<T>();
        public List():base(EHR.Generated.LiveReflection.ConstructList<T>(null)){}
        public List(int capacity):base(EHR.Generated.LiveReflection.ConstructList<T>(capacity)){}
        public List(IEnumerable<T> source):this(){try{foreach(T item in source)Add(item);}catch{Dispose();throw;}}
        internal List(ulong ownedToken,bool owned):base(ownedToken){}
        public int Count=>EHR.Generated.NativeListCalls.Count(this);
        public bool IsReadOnly=>EHR.Generated.NativeListCalls.IsReadOnly(this);
        public T this[int index]
        {
            get=>(T)EHR.Generated.ElementCodecs.Get<T>().Read(EHR.Generated.NativeListCalls.Get(this,index))!;
            set{using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(value);EHR.Generated.NativeListCalls.Set(this,index,boxed);}
        }
        public void Add(T item)
        {using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(item);using var result=EHR.Generated.NativeListCalls.ObjectCall(this,"Add","System.Int32",boxed);}
        public unsafe void RemoveRange(int index,int count)
        {
            ulong integer=EHR.Generated.ElementCodecs.Get<int>().NativeClass();
            ulong method=EHR.Generated.NativeMethods.Lookup(NativeClass,"RemoveRange",[integer,integer],EHR.Generated.FacadeRuntime.Class("mscorlib.dll","System","Void"),false);
            EHR.Generated.NativeArgument* arguments=stackalloc EHR.Generated.NativeArgument[2];arguments[0]=EHR.Generated.FacadeRuntime.Value(&index,"System.Int32");arguments[1]=EHR.Generated.FacadeRuntime.Value(&count,"System.Int32");
            using var result=EHR.Generated.FacadeRuntime.InvokeResolved(method,Token,arguments,2);
        }
        // Managed-source callback adapters read the actual native collection.
        // Native APIs requiring an actual IL2CPP delegate remain unsupported.
        public T? Find(Il2CppSystem.Predicate<T> predicate)
        {
            ArgumentNullException.ThrowIfNull(predicate);
            for(int i=0;i<Count;++i){T item=this[i];if(predicate(item))return item;}
            return default;
        }
        public bool Exists(Il2CppSystem.Predicate<T> predicate)
        {
            ArgumentNullException.ThrowIfNull(predicate);
            for(int i=0;i<Count;++i)if(predicate(this[i]))return true;
            return false;
        }
        public bool TrueForAll(Il2CppSystem.Predicate<T> predicate)
        {
            ArgumentNullException.ThrowIfNull(predicate);
            for(int i=0;i<Count;++i)if(!predicate(this[i]))return false;
            return true;
        }
        public List<T> FindAll(Il2CppSystem.Predicate<T> predicate)
        {
            ArgumentNullException.ThrowIfNull(predicate);var result=new List<T>();
            try{for(int i=0;i<Count;++i){T item=this[i];if(predicate(item))result.Add(item);}return result;}
            catch{result.Dispose();throw;}
        }
        public void ForEach(Il2CppSystem.Action<T> callback)
        {
            ArgumentNullException.ThrowIfNull(callback);int version=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this);
            for(int i=0;i<Count;++i){if(version!=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this))throw new InvalidOperationException("native list modified during callback");callback.Invoke(this[i]);}
            if(version!=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this))throw new InvalidOperationException("native list modified during callback");
        }
        public void ForEach(System.Action<T> callback)
        {
            ArgumentNullException.ThrowIfNull(callback);int version=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this);
            for(int i=0;i<Count;++i){if(version!=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this))throw new InvalidOperationException("native list modified during callback");callback(this[i]);}
            if(version!=EHR.Generated.FacadeRuntime.ReadCollectionVersion(this))throw new InvalidOperationException("native list modified during callback");
        }
        public bool Contains(T item)
        {using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(item);using var result=EHR.Generated.NativeListCalls.ObjectCall(this,"Contains","System.Boolean",boxed);return EHR.Generated.FacadeRuntime.ReadValue<bool>(result);}
        public int IndexOf(T item)
        {using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(item);using var result=EHR.Generated.NativeListCalls.ObjectCall(this,"IndexOf","System.Int32",boxed);return EHR.Generated.FacadeRuntime.ReadValue<int>(result);}
        public void Insert(int index,T item)
        {using var boxed=EHR.Generated.ElementCodecs.Get<T>().Box(item);EHR.Generated.NativeListCalls.Insert(this,index,boxed);}
        public void RemoveAt(int index)=>EHR.Generated.NativeListCalls.RemoveAt(this,index);
        public bool Remove(T item){int index=IndexOf(item);if(index<0)return false;RemoveAt(index);return true;}
        public void Clear()=>EHR.Generated.NativeListCalls.Clear(this);
        public void CopyTo(T[] array,int index)
        {
            ArgumentNullException.ThrowIfNull(array);int count=Count;
            if(index<0||index>array.Length||count>array.Length-index)throw new ArgumentOutOfRangeException(nameof(index));
            for(int i=0;i<count;++i)array[index+i]=this[i];
        }
        public Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppArrayBase<T> ToArray()
        {
            var result=new Il2CppInterop.Runtime.InteropTypes.Arrays.Il2CppArrayBase<T>(EHR.Generated.LiveCollections.Create(EHR.Generated.ElementCodecs.Get<T>().NativeClass(),Count));
            try{EHR.Generated.NativeListCalls.CopyTo(this,result);return result;}catch{result.Dispose();throw;}
        }
        public Enumerator GetEnumerator()=>new(this);
        IEnumerator<T> IEnumerable<T>.GetEnumerator()=>GetEnumerator();
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()=>GetEnumerator();
        public struct Enumerator:IEnumerator<T>
        {
            private readonly List<T> owner;
            private readonly int version;
            private int index;
            private T? current;
            internal Enumerator(List<T> list){owner=list;version=EHR.Generated.FacadeRuntime.ReadCollectionVersion(list);index=0;current=default;}
            public T Current=>current!;
            object? System.Collections.IEnumerator.Current=>index==0||index>owner.Count?throw new InvalidOperationException():current;
            private void Check(){if(version!=EHR.Generated.FacadeRuntime.ReadCollectionVersion(owner))throw new InvalidOperationException("Native collection was modified during enumeration.");}
            public bool MoveNext(){Check();if(index<owner.Count){current=owner[index++];return true;}index=owner.Count+1;current=default;return false;}
            public void Reset(){Check();index=0;current=default;}
            public void Dispose(){}
        }
    }
}
