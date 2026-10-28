using System;
namespace EHR;

// Own scalar policy. The first failure seals the affected touch controls until
// process restart; no failed gateway operation is retried from a GUI frame.
internal sealed class IOSTouchControlFailureGate(Action clear, Func<Exception,int> contain)
{
 internal bool Failed { get; private set; }
 internal int LastStatus { get; private set; }
 internal int Failures { get; private set; }
 internal bool CleanupFailed { get; private set; }
 internal T Run<T>(Func<T> action,T fallback)
 {
  if(Failed)return fallback;
  try{return action();}catch(Exception error){Fail(error);return fallback;}
 }
 internal void Run(Action action)=>Run(()=>{action();return true;},false);
 internal void Fail(Exception error)
 {
  if(Failed)return;
  Failed=true;Failures++;LastStatus=6;
  // Seal before cleanup: reentrant rendering cannot execute another request.
  try{clear();}catch{CleanupFailed=true;}
  try{int status=contain(error);LastStatus=status==0?6:status;}catch{CleanupFailed=true;}
 }
}
