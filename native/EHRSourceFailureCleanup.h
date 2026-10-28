#pragma once
#import <Foundation/Foundation.h>
// FAILURE ONLY: main thread, source callbacks deactivated before native cleanup.
// Does not alter official account/progress storage or restart a failed plugin.
FOUNDATION_EXPORT NSDictionary *EHRFullSourceFailureCleanup(void);
