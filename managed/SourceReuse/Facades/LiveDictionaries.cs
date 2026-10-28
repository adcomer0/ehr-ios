using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace EHR.Generated
{
    internal static unsafe class NativeDictionaryCalls
    {
        private static BindingSpec Spec(string member,string result,string[] parameters,bool collection=false)
            =>new("mscorlib.dll","System.Collections",collection?"ICollection":"IDictionary",member,false,false,result,parameters);
        internal static RuntimeObject Get(RuntimeObject dictionary,RuntimeObject key)
        {NativeArgument argument=FacadeRuntime.Reference(key);return FacadeRuntime.Invoke(Spec("get_Item","System.Object",["System.Object"]),dictionary.Token,&argument,1);}
        internal static void Set(RuntimeObject dictionary,RuntimeObject key,RuntimeObject value,bool add)
        {
            NativeArgument* arguments=stackalloc NativeArgument[2];arguments[0]=FacadeRuntime.Reference(key);arguments[1]=FacadeRuntime.Reference(value);
            using var result=FacadeRuntime.Invoke(Spec(add?"Add":"set_Item","System.Void",["System.Object","System.Object"]),dictionary.Token,arguments,2);
        }
        internal static bool Contains(RuntimeObject dictionary,RuntimeObject key)
        {
            NativeArgument argument=FacadeRuntime.Reference(key);
            using var result=FacadeRuntime.Invoke(Spec("Contains","System.Boolean",["System.Object"]),dictionary.Token,&argument,1);
            return FacadeRuntime.ReadValue<bool>(result);
        }
        internal static void Remove(RuntimeObject dictionary,RuntimeObject key)
        {NativeArgument argument=FacadeRuntime.Reference(key);using var result=FacadeRuntime.Invoke(Spec("Remove","System.Void",["System.Object"]),dictionary.Token,&argument,1);}
        internal static RuntimeObject NoArgs(RuntimeObject dictionary,string member,string result)
            =>FacadeRuntime.Invoke(Spec(member,result,[]),dictionary.Token,null,0);
        internal static RuntimeObject Enumerate(RuntimeObject value,bool dictionary)
            =>FacadeRuntime.Invoke(new("mscorlib.dll","System.Collections",dictionary?"IDictionary":"IEnumerable","GetEnumerator",false,false,dictionary?"System.Collections.IDictionaryEnumerator":"System.Collections.IEnumerator",[]),value.Token,null,0);
        internal static RuntimeObject Cursor(RuntimeObject cursor,string member)
            =>FacadeRuntime.Invoke(new("mscorlib.dll","System.Collections","IDictionaryEnumerator",member,false,false,"System.Object",[]),cursor.Token,null,0);
        internal static ulong NativeClass<TKey,TValue>()=>LiveReflection.MakeGenericClass(FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","Dictionary`2"),[ElementCodecs.Get<TKey>().NativeClass(),ElementCodecs.Get<TValue>().NativeClass()]);
        internal static ulong Construct<TKey,TValue>(int? capacity)
        {
            ulong open=FacadeRuntime.Class("mscorlib.dll","System.Collections.Generic","Dictionary`2");
            ulong closed=LiveReflection.MakeGenericClass(open,[ElementCodecs.Get<TKey>().NativeClass(),ElementCodecs.Get<TValue>().NativeClass()]);
            if(capacity is null)return LiveReflection.Construct(closed,[]).Detach();
            using var boxed=ElementCodecs.Get<int>().Box(capacity.Value);
            return LiveReflection.Construct(closed,[boxed]).Detach();
        }
        [UnmanagedCallersOnly(EntryPoint="ehr_generated_dictionary_self_test")]
        internal static int SelfTest(int* output,nuint count)
        {
            if(output==null||count!=5)return 4;for(int i=0;i<5;++i)output[i]=0;
            try
            {
                using var dictionary=new Il2CppSystem.Collections.Generic.Dictionary<string,int>();
                dictionary.Add("A\0\U0001F680",11);dictionary["other"]=21;dictionary["other"]=22;
                output[2]=dictionary.Count==2&&dictionary.TryGetValue("A\0\U0001F680",out int value)&&value==11&&!dictionary.TryGetValue("missing",out _)?1:0;
                int total=0,seen=0;foreach(var pair in dictionary){total+=pair.Value;++seen;}
                using var keys=dictionary.NativeKeys();
                int keyCount=0;foreach(string key in keys){if(dictionary.ContainsKey(key))++keyCount;}
                output[3]=total==33&&seen==2&&keys.Count==2&&keyCount==2?1:0;
                output[4]=dictionary.Remove("other")&&!dictionary.Remove("other")&&dictionary.Count==1?1:0;
                dictionary.Clear();output[4]=output[4]==1&&dictionary.Count==0?1:0;
                output[0]=output[2]==1&&output[3]==1&&output[4]==1?1:0;return output[1]=output[0]==1?0:5;
            }
            catch(RuntimeGatewayException exception){return output[1]=exception.Status;}catch{return output[1]=6;}
        }
    }
    public sealed class NativeCollectionView<T>:Il2CppSystem.Object,ICollection<T>,IReadOnlyCollection<T>
    {
        internal NativeCollectionView(ulong owned):base(owned){}
        public int Count=>NativeListCalls.Count(this);
        // This facade deliberately exposes a read-only live view. It never
        // stores a second managed collection as the native collection's state.
        public bool IsReadOnly=>true;
        public void Add(T item)=>throw new NotSupportedException("read-only native dictionary view");
        public bool Remove(T item)=>throw new NotSupportedException("read-only native dictionary view");
        public void Clear()=>throw new NotSupportedException("read-only native dictionary view");
        public bool Contains(T item)=>throw new RuntimeGatewayException(7,"typed native collection comparer dispatch not implemented");
        public void CopyTo(T[] array,int index)
        {
            ArgumentNullException.ThrowIfNull(array);if(index<0||index>array.Length||array.Length-index<Count)throw new ArgumentOutOfRangeException(nameof(index));
            foreach(T item in this)array[index++]=item;
        }
        public IEnumerator<T> GetEnumerator()=>new Cursor(NativeDictionaryCalls.Enumerate(this,false).Detach());
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()=>GetEnumerator();
        private sealed class Cursor: IEnumerator<T>
        {
            private readonly Il2CppSystem.Collections.IEnumerator native;
            internal Cursor(ulong owned){native=new(owned);}
            public bool MoveNext()=>native.MoveNext();public void Reset()=>native.Reset();
            public T Current
            {
                get
                {
                    using var owned=native.Current;
                    return (T)ElementCodecs.Get<T>().Read(owned is null?new RuntimeObject(0):FacadeRuntime.Retain(owned))!;
                }
            }
            object? System.Collections.IEnumerator.Current=>Current;
            public void Dispose()=>native.Dispose();
        }
    }
}
namespace Il2CppSystem.Collections.Generic
{
    public class Dictionary<TKey,TValue>:Il2CppSystem.Object,System.Collections.Generic.IDictionary<TKey,TValue>,IReadOnlyDictionary<TKey,TValue> where TKey:notnull
    {
        internal static ulong NativeClass=>EHR.Generated.NativeDictionaryCalls.NativeClass<TKey,TValue>();
        public Dictionary():base(EHR.Generated.NativeDictionaryCalls.Construct<TKey,TValue>(null)){}
        public Dictionary(int capacity):base(EHR.Generated.NativeDictionaryCalls.Construct<TKey,TValue>(capacity)){}
        internal Dictionary(ulong owned,bool takeOwnership):base(owned){}
        public int Count=>EHR.Generated.NativeListCalls.Count(this);
        public bool IsReadOnly
        {
            get{using var result=EHR.Generated.NativeDictionaryCalls.NoArgs(this,"get_IsReadOnly","System.Boolean");return EHR.Generated.FacadeRuntime.ReadValue<bool>(result);}
        }
        public TValue this[TKey key]
        {
            get{if(!ContainsKey(key))throw new KeyNotFoundException();using var boxed=EHR.Generated.ElementCodecs.Get<TKey>().Box(key);return (TValue)EHR.Generated.ElementCodecs.Get<TValue>().Read(EHR.Generated.NativeDictionaryCalls.Get(this,boxed))!;}
            set{using var boxedKey=EHR.Generated.ElementCodecs.Get<TKey>().Box(key);using var boxedValue=EHR.Generated.ElementCodecs.Get<TValue>().Box(value);EHR.Generated.NativeDictionaryCalls.Set(this,boxedKey,boxedValue,false);}
        }
        public EHR.Generated.NativeCollectionView<TKey> NativeKeys()=>new(EHR.Generated.NativeDictionaryCalls.NoArgs(this,"get_Keys","System.Collections.ICollection").Detach());
        public EHR.Generated.NativeCollectionView<TValue> NativeValues()=>new(EHR.Generated.NativeDictionaryCalls.NoArgs(this,"get_Values","System.Collections.ICollection").Detach());
        public System.Collections.Generic.ICollection<TKey> Keys=>NativeKeys();
        public System.Collections.Generic.ICollection<TValue> Values=>NativeValues();
        IEnumerable<TKey> IReadOnlyDictionary<TKey,TValue>.Keys=>Keys;
        IEnumerable<TValue> IReadOnlyDictionary<TKey,TValue>.Values=>Values;
        public void Add(TKey key,TValue value)
        {using var boxedKey=EHR.Generated.ElementCodecs.Get<TKey>().Box(key);using var boxedValue=EHR.Generated.ElementCodecs.Get<TValue>().Box(value);EHR.Generated.NativeDictionaryCalls.Set(this,boxedKey,boxedValue,true);}
        public bool ContainsKey(TKey key){using var boxed=EHR.Generated.ElementCodecs.Get<TKey>().Box(key);return EHR.Generated.NativeDictionaryCalls.Contains(this,boxed);}
        public bool TryGetValue(TKey key,out TValue value)
        {if(!ContainsKey(key)){value=default!;return false;}value=this[key];return true;}
        public bool Remove(TKey key)
        {using var boxed=EHR.Generated.ElementCodecs.Get<TKey>().Box(key);if(!EHR.Generated.NativeDictionaryCalls.Contains(this,boxed))return false;EHR.Generated.NativeDictionaryCalls.Remove(this,boxed);return true;}
        public void Clear(){using var result=EHR.Generated.NativeDictionaryCalls.NoArgs(this,"Clear","System.Void");}
        public void Add(KeyValuePair<TKey,TValue> pair)=>Add(pair.Key,pair.Value);
        public bool Contains(KeyValuePair<TKey,TValue> pair)=>throw new EHR.Generated.RuntimeGatewayException(7,"native generic pair comparer dispatch not implemented");
        public bool Remove(KeyValuePair<TKey,TValue> pair)=>throw new EHR.Generated.RuntimeGatewayException(7,"native generic pair comparer dispatch not implemented");
        public void CopyTo(KeyValuePair<TKey,TValue>[] array,int index)
        {ArgumentNullException.ThrowIfNull(array);if(index<0||index>array.Length||array.Length-index<Count)throw new ArgumentOutOfRangeException(nameof(index));foreach(var pair in this)array[index++]=pair;}
        public IEnumerator<KeyValuePair<TKey,TValue>> GetEnumerator()=>new Cursor(EHR.Generated.NativeDictionaryCalls.Enumerate(this,true).Detach());
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()=>GetEnumerator();
        private sealed class Cursor:IEnumerator<KeyValuePair<TKey,TValue>>
        {
            private readonly Il2CppSystem.Collections.IEnumerator native;
            internal Cursor(ulong owned){native=new(owned);}
            public bool MoveNext()=>native.MoveNext();public void Reset()=>native.Reset();
            public KeyValuePair<TKey,TValue> Current=>new((TKey)EHR.Generated.ElementCodecs.Get<TKey>().Read(EHR.Generated.NativeDictionaryCalls.Cursor(native,"get_Key"))!, (TValue)EHR.Generated.ElementCodecs.Get<TValue>().Read(EHR.Generated.NativeDictionaryCalls.Cursor(native,"get_Value"))!);
            object? System.Collections.IEnumerator.Current=>Current;
            public void Dispose()=>native.Dispose();
        }
    }
}
