#pragma once
#include <stddef.h>
#include <stdint.h>

// Public EOS Connect C ABI, corroborated against the exact installed SDK's
// managed Internal field declarations/offsets at runtime before first use.
// This file contains no game implementation, credential or opaque handle value.
namespace ehr_itch {
struct Credentials { int32_t apiVersion; const char *token; int32_t type; };
struct LoginOptions { int32_t apiVersion; const Credentials *credentials; const void *userLoginInfo; };
struct LoginInfo { int32_t result; void *clientData; void *localUserId; void *continuanceToken; };
using Callback = void (*)(const LoginInfo *);
using Login = void (*)(void *, const LoginOptions *, void *, Callback);
static_assert(sizeof(void *)==8 && sizeof(Credentials)==24 && sizeof(LoginOptions)==24 && sizeof(LoginInfo)==32);
static_assert(offsetof(Credentials,token)==8 && offsetof(Credentials,type)==16);
static_assert(offsetof(LoginOptions,credentials)==8 && offsetof(LoginOptions,userLoginInfo)==16);
static_assert(offsetof(LoginInfo,clientData)==8 && offsetof(LoginInfo,localUserId)==16 && offsetof(LoginInfo,continuanceToken)==24);
constexpr int32_t keyCredentialType=15, credentialsVersion=1, loginVersion=2;
constexpr size_t maxKeyBytes=8192;
// Immutable EOSSDK code-section fingerprint; re-signing its code directory
// changes neither UUID nor these instruction bytes. New SDKs fail closed.
constexpr uint8_t sdkUUID[16]={0xfc,0x5e,0x28,0x6c,0xa6,0x5f,0x30,0x2a,0xa5,0x0d,0x75,0xba,0x39,0xdd,0xc3,0xce};
constexpr uint8_t sdkTextSHA[32]={0xc9,0x76,0xc6,0x05,0x4d,0xa6,0xe4,0x17,0x79,0xfd,0x25,0xfe,0xa8,0x5a,0xac,0x96,0x4a,0x20,0x9c,0x3b,0xac,0x0e,0x68,0x14,0x71,0x39,0x8e,0xdf,0xee,0xa0,0xbb,0x95};
constexpr uintptr_t sdkLoginRVA=0x52fe78, sdkTextRVA=0x8000;
constexpr size_t sdkTextBytes=9226588;
// The pinned public runtime_class_init wrapper and its immutable no-call fast
// path prove this class flag: nonzero returns before initialization executes.
constexpr uintptr_t classInitExportRVA=0x195f1c8,classInitImplRVA=0x19be0dc;
constexpr size_t classCtorCompleteOffset=224;
constexpr uint8_t classInitExportSHA[32]={0x4c,0x41,0xf3,0x68,0x03,0xee,0xa5,0xd4,0xc4,0x7f,0x3a,0xbe,0xd7,0xda,0xf4,0x76,0xda,0x60,0x2f,0x95,0xbf,0x49,0x39,0xaa,0xe3,0x3d,0x86,0x9c,0xfd,0x2b,0xdf,0x73};
constexpr uint8_t classInitFastPathSHA[32]={0x38,0x2f,0xc6,0x43,0x18,0x06,0x0e,0x0e,0x37,0xf7,0x26,0x83,0x79,0xb2,0x35,0x28,0x6f,0x5d,0xd0,0xbc,0x8c,0x87,0xf8,0x6d,0x2e,0x56,0x74,0x43,0xed,0xe2,0x8e,0xcb};
}
