#pragma once
#import <UIKit/UIKit.h>

// An app-owned input cover, independent of the game's authentication flags.
// The normal game UI becomes reachable only after this credential's ownership
// check succeeds. Original account/consent prompts remain available afterward.
@interface EHROwnershipCover:UIScrollView
- (void)refreshOwnership;
@end
